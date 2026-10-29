# Demo image: HAProxy + Keepalived in one container (one per LB node).
# Production nodes run both as systemd services instead (see bare-metal/).
FROM alpine:3.22

RUN apk add --no-cache haproxy keepalived openssl curl socat \
    && mkdir -p /etc/haproxy/certs /etc/haproxy/errors /etc/keepalived /var/run

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY keepalived/check_haproxy.sh /usr/local/bin/check_haproxy.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/check_haproxy.sh

EXPOSE 80 443 8404 8405
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
