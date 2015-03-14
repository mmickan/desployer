#!/bin/bash
#
# puppet-bootstrap.sh
#
# Bootstrap script to deploy a working puppet agent on a fresh Ubuntu 14.04
# deployment, talking to a given puppetmaster.  The initial puppet agent run
# will wait for the Puppet CA to sign its certificate request during the
# initial bootup.  Note that this script does not configure the puppet agent
# daemon to start, so if that's required, ensure your puppetmaster instructs
# the agent to set that up on the first run.
#
# This script takes no parameters, but requires the puppetmaster variable to
# be set below.
#

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
if [ -z `which wget` ]; then
    log "Installing wget"
    [ -e /usr/bin/apt-get ] && apt-get install -y wget
    [ -e /usr/bin/yum]      && yum -y -q install wget
fi

log "Retrieving parameters from Consul"
puppetmaster=`wget -q -O- http://localhost:8500/v1/kv/nodes/$(dnsdomainname)/$(hostname)/bootstrap-profile/puppetmaster?raw`
log "puppetmaster is $puppetmaster"

if [ -e /usr/bin/apt-get ]; then
    log "Installing PuppetLabs apt repo"
    cd /root
    # PuppetLabs only supports LTS releases for Ubuntu, so use that even if
    # we're on a later version.  Note that Debian is not supported by this
    # script (yet), though it is supported by PuppetLabs.
    wget https://apt.puppetlabs.com/puppetlabs-release-trusty.deb
    dpkg -i puppetlabs-release-trusty.deb
    rm puppetlabs-release-trusty.deb
    apt-get update
elif [ -e /usr/bin/yum ]; then
    log "Installing PuppetLabs yum repo"
    # Note that this only supports RHEL6 derivatives at the moment
    yum -y -q install http://yum.puppetlabs.com/puppetlabs-release-el-6.noarch.rpm
fi

log "Installing Puppet and friends"
[ -e /usr/bin/apt-get ] && apt-get install -y puppet
[ -e /usr/bin/yum ]     && yum -y -q install puppet

log "Configuring Puppet"
sed -i '
/templatedir/d
/etckeeper/d' /etc/puppet/puppet.conf
puppet config set --section agent environment production
puppet config set --section agent report true
puppet config set --section agent show_diff true
puppet config set --section agent server $puppetmaster
puppet config set --section main stringify_facts false
puppet config set --section main postrun_command 'wget -q -O- http://localhost:8500/v1/agent/check/pass/service:puppetagent'

log "Configuring puppet agent service in Consul"
cat >/etc/consul.d/puppetagent.json <<EOF
{
    "service": {
        "name": "puppetagent",
        "check": {
            "name": "service:puppetagent",
            "TTL": "60m"
        }
    }
}
EOF
service consul reload

# we clear these rules as a workaround for an issue with puppetlabs'
# firewall module not being able to clear out unmanaged ip6tables rules and
# iptables rules in the same pass with "resources { 'iptables': purge => true }"
log "Clearing ip6tables rules"
echo -n > /etc/sysconfig/ip6tables
service ip6tables restart
# end of workaround

log "Running puppet agent"
puppet agent -t --waitforcert 10

log "Puppet agent returned '$?'"

log "Running puppet agent again to check for idempotency"
puppet agent -t

log "Puppet agent returned '$?'"
