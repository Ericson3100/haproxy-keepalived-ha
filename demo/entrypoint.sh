#!/bin/sh
# Starts HAProxy in the background and Keepalived in the foreground.
# If HAProxy dies, the container keeps running so Keepalived can detect it
# (check_haproxy.sh fails), lower its priority and hand the VIPs to the peer.
set -eu

CERT=/etc/haproxy/certs/site.pem
DOMAIN="${DEMO_DOMAIN:-example.com}"

if [ ! -s "$CERT" ]; then
    echo "[entrypoint] generating self-signed certificate for *.${DOMAIN}"
    openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
        -subj "/CN=*.${DOMAIN}" \
        -addext "subjectAltName=DNS:*.${DOMAIN},DNS:${DOMAIN}" \
        -keyout /tmp/site.key -out /tmp/site.crt >/dev/null 2>&1
    cat /tmp/site.crt /tmp/site.key > "$CERT"
    rm -f /tmp/site.key /tmp/site.crt
fi

echo "[entrypoint] validating HAProxy configuration"
haproxy -c -f /etc/haproxy/haproxy.cfg

echo "[entrypoint] starting HAProxy (${LB_NODE_NAME:-lb})"
haproxy -W -db -f /etc/haproxy/haproxy.cfg &

# Keepalived refuses config files with the executable bit set, which is how
# bind mounts from some hosts (e.g. Windows/WSL) appear. Copy with sane perms.
install -m 0644 /config/keepalived.conf /etc/keepalived/keepalived.conf
# Stale PID files survive "docker restart" and make Keepalived think it is
# already running.
rm -rf /run/keepalived /run/keepalived*.pid /run/vrrp.pid /run/checkers.pid

echo "[entrypoint] starting Keepalived"
exec keepalived --dont-fork --log-console --log-detail \
    --use-file /etc/keepalived/keepalived.conf
