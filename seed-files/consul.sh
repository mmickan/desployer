#!/bin/bash
#
# consul.sh
#
# Install and configure consul.
#
# This script takes no parameters, but requires the JOIN variable to be set
# to a comma-separated list of quoted Consul server IP addresses below.
#

##start parameters##
JOIN=
DC=
##end parameters##

# ensure a sane environment, even when running under cloud-init during boot
export HOME=/root
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

# the tail end of the FQDN is the Consul domain
CONSUL_DOMAIN=`hostname -f | sed "s/^.*\.${DC}\.//"`

log(){ echo -e "\e[32m\e[1m--> ${1}...\e[0m"; }

log "Deploying custom configuration for Consul"
mkdir -p /etc/consul.d

cat > /etc/consul.d/start_join.json <<EOF
{
    "start_join": [${JOIN}]
}
EOF

cat > /etc/consul.d/data_centre.json <<EOF
{
    "datacenter": "${DC}"
}
EOF

cat > /etc/consul.d/dns.json <<EOF
{
    "dns_config": {
        "allow_stale": true,
        "node_ttl": "5s"
    },
    "domain": "${CONSUL_DOMAIN}"
}
EOF

if [ ! -e /usr/bin/consul ]; then
    log "Installing Consul from bcandrea/consul PPA"
    apt-add-repository -y ppa:bcandrea/consul
    apt-get update
    apt-get install -y consul consul-web-ui
else
    log "Restarting Consul"
    service consul restart
fi
