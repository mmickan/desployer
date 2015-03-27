#!/bin/bash
#
# update-eth0-mac.sh
#
# Ensure that the MAC address for eth0 is stored in Consul.  Takes no
# parameters, but requires the ACL_TOKEN variable to be set to the value to
# be set to a suitable token for writing to Consul.
#

##start parameters##
ACL_TOKEN=
##end parameters##

# ensure a sane environment, even when running under cloud-init during boot
export HOME=/root
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

log(){ echo -e "\e[32m\e[1m--> ${1}...\e[0m"; }

# apt-get update if one hasn't been performed recently
[ -e /var/cache/apt/pkgcache.bin ] && if [ `find /var/cache/apt/pkgcache.bin -mmin +30` ]; then
    log "Performing apt-get update"
    apt-get update
fi

# install the tools we're going to require
if [ -z `which curl` ]; then
    log "Installing curl"
    [ -e /usr/bin/apt-get ] && apt-get install -y curl
    [ -e /usr/bin/yum ]     && yum -y -q install curl
fi

saved_mac=`curl -s "http://localhost:8500/v1/kv/nodes/$(dnsdomainname)/$(hostname)/mac-address/eth0?raw&token=${ACL_TOKEN}"`
mac=`ifconfig eth0 | awk '$4 == "HWaddr" { print $5 }'`

if [ "$mac" != "$saved_mac" ]; then
    log "Updating MAC address in Consul (old value: '${saved_mac}', new value: '${mac}'"
    echo -n "$mac" | curl -s -X PUT -o /dev/null -T - "http://localhost:8500/v1/kv/nodes/$(dnsdomainname)/$(hostname)/mac-address/eth0?token=${ACL_TOKEN}"
fi
