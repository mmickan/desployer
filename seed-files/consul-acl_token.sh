#!/bin/bash
#
# consul-acl_token.sh
#
# Provide an acl_token configuration item for Conul to allow the client a
# specific set of privileges.  Takes no parameters, but requires the
# ACL_TOKEN variable to be set to the value to be set as Consul's acl_token.
#

##start parameters##
ACL_TOKEN=
##end parameters##

# ensure a sane environment, even when running under cloud-init during boot
export HOME=/root
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

log(){ echo -e "\e[32m\e[1m--> ${1}...\e[0m"; }

log "Setting up acl_token for Consul"
mkdir -p /etc/consul.d

cat > /etc/consul.d/acl_token.json <<EOF
{
    "acl_token": "${ACL_TOKEN}"
}
EOF

# restart Consul to pick up the change if it's already running
service consul status >/dev/null 2>&1
if [ $? -eq 0 ]; then
    log "Restarting Consul"
    service consul restart
fi

