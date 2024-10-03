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
  scan-uploader:latest
```

Docker Compose
```yml
services:
  scan-uploader:
    image: scan-uploader 
    container_name: scan-uploader
    restart: unless-stopped
    volumes:
      - "./nextcloud:/app/nextcloud"
      - "./paperless:/app/paperless"
    env_file:
        - .env
```
