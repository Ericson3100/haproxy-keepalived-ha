#!/bin/sh
# Keepalived track script: exit 0 while HAProxy is alive, 1 otherwise.
# A failing script applies the negative "weight" of vrrp_script, which drops
# this node's priority below the peer and triggers a VIP failover.
if pidof haproxy >/dev/null 2>&1; then
    exit 0
fi
exit 1
