# Installation guide (RHEL-family: Rocky / Alma / RHEL 9)

Step-by-step installation of HAProxy (built from source), Keepalived, rsyslog
and Cockpit on **both** load-balancer nodes. Run everything as root.
Commands for Debian/Ubuntu are similar (`apt`, `ufw`), package names differ.

## 1. Service user

```bash
useradd -r -M -s /sbin/nologin haproxy
```

## 2. Build dependencies

| Package | Why |
|---|---|
| `gcc`, `make` | HAProxy is written in C and built with make |
| `pcre2-devel` | regular expressions in ACLs |
| `zlib-devel` | HTTP compression |
| `openssl-devel` | TLS termination / re-encryption |
| `systemd-devel` | `Type=notify` integration (`USE_SYSTEMD`) |
| `tar`, `wget` | download and unpack the sources |

```bash
dnf install -y gcc make pcre2-devel zlib-devel openssl-devel systemd-devel tar wget
dnf groupinstall -y 'Development Tools'
dnf install -y rsyslog keepalived cockpit socat
systemctl enable --now cockpit.socket
```

## 3. Firewall

```bash
dnf install -y firewalld
systemctl enable --now firewalld
firewall-cmd --permanent --add-protocol=vrrp    # Keepalived adverts (IP protocol 112)
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --permanent --add-port=6443/tcp    # only if you use TCP passthrough
firewall-cmd --permanent --add-port=9090/tcp    # Cockpit (restrict to admins!)
firewall-cmd --reload
firewall-cmd --list-all
```

## 4. Build and install HAProxy

```bash
HAPROXY_VERSION=3.2.2        # pick the latest 3.2.x LTS release
wget https://www.haproxy.org/download/3.2/src/haproxy-${HAPROXY_VERSION}.tar.gz
tar -xzf haproxy-${HAPROXY_VERSION}.tar.gz
cd haproxy-${HAPROXY_VERSION}

# OpenSSL, PCRE2, zlib, systemd notify and the built-in Prometheus exporter
make -j"$(nproc)" TARGET=linux-glibc USE_PCRE2=1 USE_OPENSSL=1 USE_ZLIB=1 USE_SYSTEMD=1 USE_PROMEX=1
make install

which haproxy                       # /usr/local/sbin/haproxy
mv /usr/local/sbin/haproxy /usr/sbin/   # path expected by haproxy.service
haproxy -vv | grep -E 'version|PROMEX'
```

## 5. Directories and base files

```bash
mkdir -p /etc/haproxy/conf.d /etc/haproxy/certs /etc/haproxy/errors /var/lib/haproxy
chown -R haproxy:haproxy /var/lib/haproxy

# From this repository:
cp bare-metal/etc/sysconfig/haproxy              /etc/sysconfig/haproxy
cp bare-metal/etc/haproxy/haproxy.cfg            /etc/haproxy/haproxy.cfg
cp bare-metal/etc/haproxy/errors/*.html          /etc/haproxy/errors/
cp bare-metal/usr/lib/systemd/system/haproxy.service /usr/lib/systemd/system/
cp bare-metal/etc/sysctl.d/99-haproxy-vip.conf   /etc/sysctl.d/
sysctl --system
```

Edit `/etc/haproxy/haproxy.cfg`: VIPs, hostnames, backend servers, admin
network and the stats user hashes (`mkpasswd -m sha-512` or
`openssl passwd -6`).

## 6. Certificates

HAProxy expects one PEM per certificate containing **certificate + private key
+ intermediate chain**:

```bash
install -m 0644 example.com.crt  /etc/pki/tls/certs/
install -m 0644 ca-chain.crt     /etc/pki/tls/certs/
install -m 0600 example.com.key  /etc/pki/tls/private/

cat /etc/pki/tls/certs/example.com.crt \
    /etc/pki/tls/private/example.com.key \
    /etc/pki/tls/certs/ca-chain.crt > /etc/haproxy/certs/example.com.pem
chmod 0600 /etc/haproxy/certs/example.com.pem

# Only if you enable DHE ciphers (ssl-dh-param-file):
openssl dhparam -out /etc/haproxy/dhparams.pem 4096
```

For several domains add more `crt` arguments to the `bind` line (SNI selects
the right one) or point `crt` at the whole directory.

## 7. Logging (rsyslog + logrotate)

```bash
cp bare-metal/etc/rsyslog.d/haproxy.conf    /etc/rsyslog.d/
cp bare-metal/etc/rsyslog.d/keepalived.conf /etc/rsyslog.d/
cp bare-metal/etc/logrotate.d/haproxy       /etc/logrotate.d/
cp bare-metal/etc/logrotate.d/keepalived    /etc/logrotate.d/
mkdir -p /var/log/haproxy/hosts /var/log/keepalived

systemctl enable --now rsyslog
systemctl restart rsyslog
logrotate -d /etc/logrotate.d/haproxy     # dry run, shows what would happen
logrotate -f /etc/logrotate.d/haproxy     # force one rotation to test
```

## 8. Keepalived

```bash
cp /etc/keepalived/keepalived.conf /etc/keepalived/keepalived.conf.orig
# node 1:
cp bare-metal/etc/keepalived/keepalived-node1.conf /etc/keepalived/keepalived.conf
# node 2:
cp bare-metal/etc/keepalived/keepalived-node2.conf /etc/keepalived/keepalived.conf

install -m 0755 bare-metal/etc/keepalived/check_haproxy.sh /etc/keepalived/check_haproxy.sh
```

Edit both files: interface name, VIPs, `virtual_router_id` (unique per L2
segment, identical on both nodes for the same instance) and `auth_pass`
(same on both nodes, max 8 characters).

## 9. Start everything

```bash
haproxy -c -f /etc/haproxy/haproxy.cfg
keepalived -t -f /etc/keepalived/keepalived.conf

systemctl daemon-reload
systemctl enable --now haproxy
systemctl enable --now keepalived

systemctl status haproxy keepalived rsyslog
```

## 10. Verify

```bash
ip -4 addr show dev eth0                     # VIPs present on the MASTER
journalctl -u keepalived -b -n 200 | grep -E 'VI_|MASTER|BACKUP|FAULT'
curl -k --resolve app1.example.com:443:192.0.2.100 https://app1.example.com/
echo "show stat" | socat stdio /var/lib/haproxy/stats \
  | cut -d, -f1,2,5-11,18,24,27,30,36,50,37,56,57,62 | column -s, -t

# Failover test: stop HAProxy on node 1 and watch the VIP move to node 2
systemctl stop haproxy          # on node 1
ip -4 addr show dev eth0        # on node 2 -> now has 192.0.2.100
systemctl start haproxy         # on node 1 -> VIP returns (preempt)
```
