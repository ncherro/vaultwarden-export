FROM alpine:3.19

RUN apk add --no-cache \
    nodejs \
    npm \
    rclone \
    curl \
    tzdata \
    && npm install -g @bitwarden/cli@2024.9.0 \
    && rm -rf /root/.npm \
    && mkdir -p "/root/.config/Bitwarden CLI" \
    && echo '{}' > "/root/.config/Bitwarden CLI/data.json" \
    && mkdir -p /root/.config/rclone \
    && touch /root/.config/rclone/rclone.conf

COPY lib/ /lib/
COPY entrypoint.sh /entrypoint.sh
COPY backup.sh /backup.sh
RUN chmod +x /entrypoint.sh /backup.sh

ENTRYPOINT ["/entrypoint.sh"]
