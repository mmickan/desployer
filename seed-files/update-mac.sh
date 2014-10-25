#!/bin/bash
#
# update-eth0-mac.sh
#
# Ensure that the MAC address for eth0 is stored in Consul.
#

# ensure a sane environment, even when running under cloud-init during boot
export HOME=/root
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

log(){ echo -e "\e[32m\e[1m--> ${1}...\e[0m"; }

# apt-get update if one hasn't been performed recently
if [ `find /var/cache/apt/pkgcache.bin -mmin +30` ]; then
    log "Performing apt-get update"
    apt-get update
fi

# install the tools we're going to require
if [ -z `which wget` ]; then
    log "Installing wget"
    apt-get install -y wget
fi

saved_mac=`wget -q -O- http://localhost:8500/v1/kv/nodes/$(dnsdomainname)/$(hostname)/mac-address/eth0?raw`
mac=`ifconfig eth0 | awk '$4 == "HWaddr" { print $5 }'`

if [ "$mac" != "$saved_mac" ]; then
    log "Updating MAC address in Consul (old value: '${saved_mac}', new value: '${mac}'"
    wget -q --method=PUT --body-data="$mac" http://localhost:8500/v1/kv/nodes/$(dnsdomainname)/$(hostname)/mac-address/eth0
fi
