FROM alpine:3.19

RUN apk add --no-cache \
    nodejs \
    npm \
    curl \
    tzdata \
    bash \
    unzip \
    && curl -fsSL https://rclone.org/install.sh | bash

RUN npm install -g @bitwarden/cli@2025.2.0 \
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