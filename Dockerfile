FROM alpine:3.20
WORKDIR /app

RUN ["apk", "add", "--no-cache", "bash", "inotify-tools", "curl", "jq"]

COPY ["./src", "/app"]

USER 1000:1000

ENTRYPOINT ["bash", "main.sh"]
