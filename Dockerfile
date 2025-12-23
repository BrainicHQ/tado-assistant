FROM ghcr.io/s1adem4n/tado-api-proxy:main

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends bash curl jq tzdata ca-certificates coreutils util-linux && \
    rm -rf /var/lib/apt/lists/* && \
    if ! id -u appuser >/dev/null 2>&1; then useradd -m appuser; fi && \
    chmod 755 /app && \
    printf '%s\n' \
    '#!/bin/sh' \
    'if [ "$(id -u)" = "0" ]; then' \
    '  exec /usr/sbin/runuser -u appuser -- /app "$@"' \
    'fi' \
    'exec /app "$@"' \
    > /usr/local/bin/tado-api-proxy && \
    chmod 755 /usr/local/bin/tado-api-proxy

COPY tado-assistant.sh /usr/local/bin/tado-assistant.sh
COPY install.sh /usr/local/bin/install.sh

RUN chmod +x /usr/local/bin/tado-assistant.sh /usr/local/bin/install.sh && \
    mkdir -p /var/log && \
    chown appuser:appuser /var/log && \
    touch /var/log/tado-assistant.log && \
    chown appuser:appuser /var/log/tado-assistant.log

ENV TADO_PROXY_CHROME_EXECUTABLE=/headless-shell/headless-shell

ENTRYPOINT ["/bin/bash", "-c", \
    "set -e; \
    if [ ! -s /etc/tado-assistant.env ]; then \
        SUDO_USER=appuser /usr/local/bin/install.sh; \
        chown appuser:appuser /etc/tado-assistant.env; \
    fi; \
    chown appuser:appuser /etc/tado-assistant.env 2>/dev/null || true; \
    exec /usr/sbin/runuser -u appuser -- /usr/local/bin/tado-assistant.sh"]
