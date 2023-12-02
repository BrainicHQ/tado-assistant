FROM alpine:latest

RUN apk add --no-cache bash curl jq

COPY tado-assistant.sh /usr/local/bin/tado-assistant.sh
RUN chmod +x /usr/local/bin/tado-assistant.sh

ENTRYPOINT ["/usr/local/bin/tado-assistant.sh"]