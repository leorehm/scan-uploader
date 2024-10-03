#/bin/bash

echo "Starting Scan Uploader"

############################################################
# Nextcloud
############################################################

run_nextcloud () {
	echo "############################################################"
	echo "Starting Nextcloud Daemon"
	echo ""
	echo "Nextcloud URL:         $NEXTCLOUD_URL"
	echo "Nextcloud User:        $NEXTCLOUD_USER"
	echo "Destination Directory: $NEXTCLOUD_DEST_DIR"
	echo ""

	local CONSUME_DIR="./nextcloud/consume"
	local FAILED_DIR="./nextcloud/failed"

	mkdir -p $CONSUME_DIR 2>/dev/null
	mkdir -p $FAILED_DIR 2>/dev/null

	# Start file watcher
	inotifywait -m -e close_write --format '%f' $CONSUME_DIR | while read FILE_NAME; do
	FILE_PATH="$CONSUME_DIR/$FILE_NAME"
	echo "New file detected"

	TARGET_URL="$NEXTCLOUD_URL/remote.php/dav/files/$NEXTCLOUD_USER/$NEXTCLOUD_DEST_DIR/$FILE_NAME"
	echo "Uploading $FILE_NAME to $TARGET_URL"

		if curl -u $NEXTCLOUD_USER:$NEXTCLOUD_PASS -T $FILE_PATH $TARGET_URL; then
			echo "Upload successful"
			rm -f -v $FILE_PATH
		else
			echo "Error during upload, moving to $FAILED_DIR"
			mv -f $FILE_PATH $FAILED_DIR
		fi
	done &
}

############################################################
# Paperless 
############################################################

run_paperless () {
	echo "############################################################"
	echo "Starting Paperless Daemon"

	local CONSUME_DIR="./paperless/consume"
	local FAILED_DIR="./paperless/failed"

	mkdir -p $CONSUME_DIR 2>/dev/null
	mkdir -p $FAILED_DIR 2>/dev/null


  inotifywait -r -m -e close_write --format '%w%f' "$CONSUME_DIR" | while read FILE_PATH; do
  echo "New file detected: $FILE_PATH"

    # ./consume/user/file.pdf -> user/file.pdf
    local FILE_NAME="$(echo $FILE_PATH | sed "s;${CONSUME_DIR}/;;")"
    # user/file.pdf -> user and file.pdf -> . 
    local FILE_DIR="$(dirname $FILE_NAME)"

    echo "Document: $FILE_PATH"
    echo "File directory: $FILE_DIR"

    status=$(paperless_create_document $FILE_NAME $FILE_DIR $AUTH_TOKEN)

    if [[ $status = 0 ]]; then
      echo "Deleting $FILE_PATH"
      rm -f $FILE_NAME
    else
      echo "Moving $FILE_PATH to $FAILED_DIR"
      mv -f $FILE_PATH $FAILED_DIR
    fi
   
  done &
}

paperless_create_document () {
  # Create paperless document and set owner
  # Return 0 if successful
  local FILE_NAME=$1
  local FILE_DIR=$2

  local AUTH_TOKEN=$(echo -n "${PAPERLESS_USER}:${PAPERLESS_PASS}" | base64 -w 0)

  # Create document
  echo "Creating new paperless document"
  local TASK_ID=$(curl --show-error --fail --silent \
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
  local TASK_ID=$(echo $TASK_ID | tr -d '"')

  # Set owner id
  if [ "$FILE_DIR" = "." ]; then
    local OWNER_ID=null
  else
    local OWNER_ID="$(echo $FILE_DIR | sed 's/_.*$//')"
  fi
  
  # Get task and check status
  while [[ ! "$TASK_STATUS" =~ ^(SUCCESS|REVOKED|FAILURE)$ ]]; do
    sleep 4

    echo "Getting consumption task '$TASK_ID'"
    local TASK_INFO=$(curl --show-error --fail --silent \
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

    local TASK_STATUS=$(echo $TASK_INFO | jq -r ".[0].status")
    echo "Task status: $TASK_STATUS"
  done

  echo $TASK_INFO | jq -r '.[0].result'
  
  if [[ "$TASK_STATUS" =~ ^(FAILURE|REVOKED)$ ]]; then
    echo "Consumption exited with status '$TASK_STATUS'"
    return 1
  fi

  # Get document id
  local DOCUMENT_ID=$(echo $TASK_INFO | jq -r ".[0].related_document")
  
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
# Main 
############################################################

if [ "$NEXTCLOUD_ENABLED" = "true" ]; then
	run_nextcloud
fi

sleep 1		# keeps stdout in readable order

if [ "$PAPERLESS_ENABLED" = "true" ]; then
	run_paperless
fi

sleep infinity
