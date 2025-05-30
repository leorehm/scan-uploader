#/bin/bash

echo "Starting Scan Uploader..."

set -u

############################################################
# Setup 
############################################################

CONSUME_DIR="./consume"
FAILED_DIR="./failed"

NEXTCLOUD_CONSUME_DIR="$(realpath "$CONSUME_DIR/nextcloud")"
NEXTCLOUD_FAILED_DIR="$(realpath "$FAILED_DIR/nextcloud")"
PAPERLESS_CONSUME_DIR="$(realpath "$CONSUME_DIR/paperless")"
PAPERLESS_FAILED_DIR="$(realpath "$FAILED_DIR/paperless")"

mkdir -p \
	"$NEXTCLOUD_CONSUME_DIR" "$NEXTCLOUD_FAILED_DIR" \
	"$PAPERLESS_CONSUME_DIR" "$PAPERLESS_FAILED_DIR" \
	2>/dev/null


ALLOWED_EXTENSIONS=("pdf" "jpg" "jpeg" "png" "tif" "tiff" "bmp" "gif")

############################################################
# Utility fuctions 
############################################################

is_allowed_filetype() {
	local FILE="$1"
	local EXT="${FILE##*.}"
	EXT="${EXT,,}"	# convert to lower case

	for ALLOWED in "${ALLOWED_EXTENSIONS[@]}"; do
		if [[ "$EXT" == "$ALLOWED" ]]; then
			return 0
		fi
	done

	return 1
}

############################################################
# Nextcloud
############################################################

process_nextcloud () {
	local FILE_PATH="$1"
	local FILE_NAME

	FILE_NAME="$(basename "$FILE_PATH")"
	TARGET_URL="$NEXTCLOUD_URL/remote.php/dav/files/$NEXTCLOUD_USER/$NEXTCLOUD_DEST_DIR/$FILE_NAME"

	if ! is_allowed_filetype "$FILE_NAME"; then
		echo "Unsupported file type: $FILE_PATH"
		mv -f -v $FILE_PATH $NEXTCLOUD_FAILED_DIR
		return
	fi

	echo "Uploading $FILE_NAME to Nextcloud ($TARGET_URL)"

	if curl -u "$NEXTCLOUD_USER:$NEXTCLOUD_PASS" -T "$FILE_PATH" "$TARGET_URL"; then
		echo "Nextcloud upload successful: $FILE_NAME"
		rm -f -v "$FILE_PATH"
	else
		echo "Nextcloud upload failed: $FILE_NAME"
		echo "Moving to failed directory..."
		mv -f "$FILE_PATH" "$FAILED_DIR"
	fi
}

############################################################
# Paperless 
############################################################

process_paperless () {
	local FILE_PATH="$1"
	local FILE_NAME FILE_DIR

	FILE_NAME="$(basename "$FILE_PATH")"
	FILE_DIR="$(dirname "${FILE_PATH#PAPERLESS_CONSUME_DIR/}")"

	if ! is_allowed_filetype "$FILE_NAME"; then
		echo "Unsupported file type: $FILE_PATH"
		mv -f -v "$FILE_PATH" "$PAPERLESS_FAILED_DIR"
		return
	fi

	echo "Uploading $FILE_PATH to paperless"

	status=$(paperless_create_document "$FILE_NAME" "$FILE_DIR")

	if [[ $status = 0 ]]; then
		echo "Deleting $FILE_PATH"
		rm -f -v "$FILE_NAME"
	else
		echo "Moving $FILE_PATH to $FAILED_DIR"
		mv -f "$FILE_PATH" "$FAILED_DIR"
	fi
}

paperless_create_document () {
  # Create paperless document and set owner
  # Return 0 if successful
  local FILE_NAME=$1
  local FILE_DIR=$2

	local AUTH_TOKEN TASK_ID
	AUTH_TOKEN=$(echo -n "${PAPERLESS_USER}:${PAPERLESS_PASS}" | base64 -w 0)

  # Create document
  echo "Creating new paperless document"
  TASK_ID=$(curl --show-error --fail --silent \
    --request POST \
    --location "$PAPERLESS_URL/api/documents/post_document/" \
    --header "Authorization: Basic $AUTH_TOKEN" \
    --header "Content-Type: multipart/form-data" \
    --form "document=@\"${FILE_PATH}\"" \
    2>&1
  )
  status=$?

  if [ $status != 0 ]; then
    echo "Failed to create document: $status"
    return $status
  fi
  
  echo "Successfully posted document. Task Id: $TASK_ID"

  # Remove "" from task id
  TASK_ID=$(echo $TASK_ID | tr -d '"')

  # Set owner id
	local OWNER_ID
  if [[ "$FILE_DIR" == "$PAPERLESS_CONSUME_DIR" ]]; then
    OWNER_ID=null
  else
    OWNER_ID="$(basename "$FILE_DIR" | sed 's/_.*$//')"
  fi
  
  # Get task and check status
	local TASK_STATUS TASK_INFO
	TASK_STATUS="INIT"

  while [[ ! "$TASK_STATUS" =~ ^(SUCCESS|REVOKED|FAILURE)$ ]]; do
    sleep 5 

    echo "Getting consumption task '$TASK_ID'"
    TASK_INFO=$(curl --show-error --fail --silent \
      --request GET \
      --location "$PAPERLESS_URL/api/tasks/?task_id=$TASK_ID" \
      --header "Authorization: Basic $AUTH_TOKEN" \
      2>&1
    )
    status=$?

    if [ $status != 0 ]; then
      echo "Failed to get task info: $status"
      return 1
    fi

    TASK_STATUS=$(echo $TASK_INFO | jq -r ".[0].status")
    echo "Task status: $TASK_STATUS"
  done

  echo $TASK_INFO | jq -r '.[0].result'
  
  if [[ "$TASK_STATUS" =~ ^(FAILURE|REVOKED)$ ]]; then
    echo "Consumption exited with status '$TASK_STATUS'"
    return 1
  fi

  # Get document id
	local DOCUMENT_ID
  DOCUMENT_ID=$(echo $TASK_INFO | jq -r ".[0].related_document")
  
  if [ -z $DOCUMENT_ID ]; then
    echo "Failed getting document id"
    return 1
  fi
  
  # Set document owner
  # This will return 404 even when successful if the current user 
  # does not have superuser permissions
  echo "Setting owner of document $DOCUMENT_ID to $OWNER_ID"
  local DOCUMENT_INFO=$(curl --show-error --fail \
    --request PATCH \
    --location "$PAPERLESS_URL/api/documents/$DOCUMENT_ID/" \
    --header "Authorization: Basic $AUTH_TOKEN" \
    --header "Content-Type: application/json" \
    --data "{\"owner\": $OWNER_ID}" \
    2>&1
  )
  status=$?

  if [ $status != 0 ]; then
    echo "Failed to set document owner: $status"
    return 1
  fi

  return 0
}

############################################################
# File watcher
############################################################

echo "############################################################"
echo "Starting file watcher"

inotifywait -r -m -e close_write --format "%w%f" \
	"$NEXTCLOUD_CONSUME_DIR" "$PAPERLESS_CONSUME_DIR" | while read -r FILE_PATH; do

	echo "Detected new file: $FILE_PATH"

	if [[ "$FILE_PATH" == "$NEXTCLOUD_CONSUME_DIR"* ]]; then
		process_nextcloud "$FILE_PATH"
	elif [[ "$FILE_PATH" == "$PAPERLESS_CONSUME_DIR"* ]]; then
		process_paperless "$FILE_PATH"
	else
		echo "Unknown file source: $FILE_PATH"
	fi
done

