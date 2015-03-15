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
ACL_DC=
KEY=
##end parameters##

# ensure a sane environment, even when running under cloud-init during boot
export HOME=/root
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

# the tail end of the FQDN is the Consul domain
CONSUL_DOMAIN=`hostname -f | sed "s/^.*\.${DC}\.//"`

# consul version
VERSION=0.5.0

log(){ echo -e "\e[32m\e[1m--> ${1}...\e[0m"; }

log "Deploying custom configuration for Consul"
mkdir -p /etc/consul.d

cat > /etc/consul.d/config.json <<EOF
{
    "data_dir": "/var/lib/consul",
    "datacenter": "${DC}",
    "dns_config": {
        "allow_stale": true,
        "node_ttl": "5s"
    },
    "domain": "${CONSUL_DOMAIN}",
    "start_join": [${JOIN}],
    "acl_datacenter": "${ACL_DC}",
    "encrypt": "${KEY}"
}
EOF

if [ ! -e /usr/bin/consul ]; then

    # there's a package available for Ubuntu to make things easy
    log "Installing Consul from bcandrea/consul PPA"
    apt-add-repository -y ppa:bcandrea/consul
    apt-get update
    apt-get install -y consul consul-web-ui

else
    log "Restarting Consul"
    service consul restart
fi
