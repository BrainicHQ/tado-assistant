FROM alpine:latest

RUN apk add --no-cache bash curl jq tzdata ca-certificates && \
    update-ca-certificates && \
    apk add --no-cache coreutils

COPY tado-assistant.sh /usr/local/bin/tado-assistant.sh
COPY install.sh /usr/local/bin/install.sh

RUN chmod +x /usr/local/bin/tado-assistant.sh /usr/local/bin/install.sh && \
    mkdir -p /var/log && \
    touch /var/log/tado-assistant.log && \
    chmod 666 /var/log/tado-assistant.log

ENTRYPOINT ["/bin/sh", "-c", \
    "if [ ! -s /etc/tado-assistant.env ]; then \
        /usr/local/bin/install.sh; \
    fi; \
    exec /usr/local/bin/tado-assistant.sh"]