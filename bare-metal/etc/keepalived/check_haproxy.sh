#!/bin/bash
# Keepalived track script (chmod 0755, owned by root).
# Exit 0 = HAProxy healthy, anything else = unhealthy -> VIP failover.
pidof haproxy >/dev/null 2>&1 || exit 1

# Optional deeper check: make sure HAProxy still answers on the runtime socket.
# echo "show info" | socat -t 2 stdio /var/lib/haproxy/stats >/dev/null 2>&1 || exit 1

exit 0
