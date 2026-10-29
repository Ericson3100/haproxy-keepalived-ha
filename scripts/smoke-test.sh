#!/bin/sh
# Smoke test, run from the client container:
#   docker compose exec client sh /scripts/smoke-test.sh
# Sends requests through the virtual IPs and prints which backend / LB node answered.
set -u

VIP1="${VIP1:-10.77.0.100}"
VIP2="${VIP2:-10.77.0.101}"

req() { # host vip [path]
    curl -sk --max-time 3 --resolve "$1:443:$2" "https://$1${3:-/}" -D - -o /tmp/body \
        | tr -d '\r' | awk -v h="$1" -v v="$2" '
            NR==1 {code=$2}
            tolower($1)=="x-lb-node:" {node=$2}
            END {printf "%-18s via %-12s -> HTTP %s  lb=%s", h, v, code, node}'
    printf "  backend=%s\n" "$(grep -m1 '^Hostname:' /tmp/body 2>/dev/null | cut -d' ' -f2)"
}

echo "== Round robin on app1 through VIP1 =="
for i in 1 2 3 4; do req app1.example.com "$VIP1"; done

echo "== Least-conn on api through VIP2 =="
for i in 1 2 3 4; do req api.example.com "$VIP2"; done

echo "== app2 (single server) =="
req app2.example.com "$VIP1"

echo "== Unknown host -> custom 404 =="
req unknown.example.com "$VIP1"

echo "== HTTP -> HTTPS redirect =="
curl -s -o /dev/null -w "http://app1.example.com -> %{http_code} %{redirect_url}\n" \
    --resolve "app1.example.com:80:$VIP1" http://app1.example.com/
