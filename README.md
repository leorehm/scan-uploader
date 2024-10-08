# Nextcloud Scan Uploader

A simple tool for automatically uploading scans or any other files to Nextcloud or Paperless-ngx.

## Installation

Docker 
```sh
docker run \
  --name scan-uploader \
  --env-file=.env \
  --volume ./nextcloud:/app/nextcloud \
  --volume ./paperless:/app/paperless \
  ghcr.io/leorehm/scan-uploader:latest
```

Docker Compose
```yml
services:
  scan-uploader:
    image: "ghcr.io/leorehm/scan-uploader:latest"
    container_name: scan-uploader
    restart: unless-stopped
    volumes:
      - "./nextcloud:/app/nextcloud"
      - "./paperless:/app/paperless"
    env_file:
        - .env
```

Environment variables
```
# Nextcloud
NEXTCLOUD_ENABLED=true
NEXTCLOUD_URL=https://cloud.domain.tld
NEXTCLOUD_USER=username
NEXTCLOUD_PASS=password
NEXTCLOUD_DEST_DIR=Scan

# Paperless
PAPERLESS_ENABLED=true
PAPERLESS_URL=https://paperless.domain.tld
PAPERLESS_USER=username
PAPERLESS_PASS=password
```
