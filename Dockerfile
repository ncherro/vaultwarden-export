FROM alpine:3.19

RUN apk add --no-cache \
    nodejs \
    npm \
    rclone \
    tzdata \
    && npm install -g @bitwarden/cli@2024.9.0 \
    && rm -rf /root/.npm

COPY entrypoint.sh /entrypoint.sh
COPY backup.sh /backup.sh
RUN chmod +x /entrypoint.sh /backup.sh

ENTRYPOINT ["/entrypoint.sh"]
