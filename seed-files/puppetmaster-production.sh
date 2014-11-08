#!/bin/bash
#
# puppetmaster-production.sh
#
# Deploy puppet manifests to the local puppetmaster from the git repository
# as provided via Consul at
# /v1/kv/nodes/<domain>/<host>/bootstrap-profile/puppet-repo.  Keeping this
# as a separate step from the initial bootstrap (puppetmaster-bootstrap.sh)
# allows us to provision a puppetmaster host without having to provide any
# manifests, or with minimal manifests that don't configure the puppetmaster
# host.
#
# This script takes no parameters.
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

log "Retrieving parameters from Consul"
puppetrepo=`wget -q -O- http://localhost:8500/v1/kv/nodes/$(dnsdomainname)/$(hostname)/bootstrap-profile/puppet-repo?raw`

if [[ -z $puppetrepo ]]; then
    log "No puppetrepo specified: skipping deployment of production puppet manifests"
    exit
else
    log "puppetrepo is '$puppetrepo'"
fi

log "Deploying puppet manifests to 'production' Puppet environment"
git clone $puppetrepo /tmp/production
cd /tmp/production

git config --global user.name 'Puppetmaster Bootstrap'
git config --global user.email mark.mickan@articul-8.com
git remote add puppetmaster /srv/puppet.git
git push puppetmaster HEAD:production

log "Running puppet agent"
puppet agent -t --environment production

log "Puppet agent returned '$?'"

log "Running puppet agent again to check for idempotency"
puppet agent -t --environment production

log "Puppet agent returned '$?'"
