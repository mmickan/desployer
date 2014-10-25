#!/bin/bash
#
# unbound.sh
#
# Install and configure unbound.
#
# This script takes no parameters; all configuration is pulled from Consul.
#

# ensure a sane environment, even when running under cloud-init during boot
export HOME=/root
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

log(){ echo -e "\e[32m\e[1m--> ${1}...\e[0m"; }

# run apt-get update if it hasn't been run recently
if [ `find /var/cache/apt/pkgcache.bin -mmin +30` ]; then
    log "Performing apt-get update"
    apt-get update
fi

# install the tools we're going to require
if [ -z `which wget` ]; then
    log "Installing wget"
    apt-get install -y wget
fi

log "Retrieving parameters from Consul"
upstream_dns=`wget -q -O- http://localhost:8500/v1/kv/common/upstream-dns?raw`

data_centre=`hostname -f | sed 's/^.*\.node\.\([^\.]*\).*$/\1/'`
consul_domain=`hostname -f | sed 's/^.*\.node\.[^\.]*\.\(.*\)$/\1/'`

log "Deploying custom configuration for Unbound"
mkdir -p /etc/unbound/unbound.conf.d

cat > /etc/unbound/unbound.conf.d/consul.conf <<EOF
server:
    do-not-query-localhost: no
    private-domain: "${consul_domain}."
    domain-insecure: "${consul_domain}."

forward-zone:
    name: "${consul_domain}."
    forward-addr: 127.0.0.1@8600

forward-zone:
    name: "."
    forward-addr: ${upstream_dns}
EOF

if [ ! -e /usr/sbin/unbound ]; then
    log "Installing Unbound"
    apt-get install -y unbound
else
    log "Restarting Unbound"
    service unbound restart
fi

log "Reconfiguring DNS resolver to use Unbound and Consul"
resolvconf --disable-updates
cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
search node.${data_centre}.${consul_domain} service.${data_centre}.${consul_domain}
EOF
