#!/bin/bash
#
# puppetmaster-bootstrap.sh
#
# Boostrap script to deploy a working puppetmaster on a fresh Ubuntu host.
# Includes setup of a bare git repo in /srv/puppet.git with a post-receive
# hook to deploy configuration to Puppet environment directories named after
# corresponding git branches and deploy modules using librarian-puppet.
#
# This script takes no parameters.
#

# ensure a sane environment, even when running under cloud-init during boot
export HOME=/root
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

log(){ echo -e "\e[32m\e[1m--> ${1}...\e[0m"; }

log "Retrieving parameters from Consul"
autosign=`wget -q -O- http://localhost:8500/v1/kv/nodes/$(dnsdomainname)/$(hostname)/bootstrap-profile/autosign?raw`
log "autosign is '$autosign'"

log "Installing PuppetLabs apt repo"
apt-get update
apt-get install -y wget
cd /root
wget https://apt.puppetlabs.com/puppetlabs-release-trusty.deb
dpkg -i puppetlabs-release-trusty.deb
rm puppetlabs-release-trusty.deb
apt-get update

log "Installing Puppet and friends"
apt-get install -y git rake make ruby ruby-dev puppet puppetmaster

log "Configuring Puppet"
fqdn=$(hostname -f)
data_centre=`echo $fqdn | sed 's/^.*\.node\.\([^\.]*\).*$/\1/'`
consul_domain=`echo $fqdn | sed 's/^.*\.node\.[^\.]*\.\(.*\)$/\1/'`
sed -i '/templatedir/d' /etc/puppet/puppet.conf
puppet config set --section main pluginsync true
#puppet config set --section main parser future
#puppet config set --section main evaluator current
puppet config set --section main dns_alt_names puppet,puppet.service.${data_centre}.${consul_domain},$(hostname),$fqdn
puppet config set --section main environmentpath \$confdir/environments
puppet config set --section agent environment production
puppet config set --section agent report true
puppet config set --section agent show_diff true
puppet config set --section agent server $fqdn
puppet config set --section master environment production
if [ ! -z $autosign ]; then
    puppet config set --section master autosign $autosign
fi
mkdir -p /etc/puppet/environments
chgrp -R puppet /etc/puppet/environments

# status is used by Consul's puppet service monitor
sed -i \
    's|.*deny everything else.*|path /status\nmethod find\nallow *\n\n&|' \
    /etc/puppet/auth.conf

# need to regenerate certificate because we changed dns_alt_names
log "Regenerating Puppet certificate"
find $(puppet config print ssldir) -name $(puppet config print certname).pem -exec rm -f {} \;
puppet cert generate $(puppet config print certname)

log "Installing librarian-puppet"
gem install --no-rdoc --no-ri librarian-puppet
mkdir -p /var/cache/librarian-puppet

log "Setting up local git repo for Puppet environments"
git init --bare --shared=group /srv/puppet.git
chgrp -R puppet /srv/puppet.git
cd /srv/puppet.git
git symbolic-ref HEAD refs/heads/production
git clone /srv/puppet.git /var/cache/puppet-git

cat > /srv/puppet.git/hooks/post-receive <<'EOF'
#!/bin/bash

umask 002
unset GIT_DIR

while read oldrev newrev ref
do
    branch=$(echo $ref | cut -d/ -f3)
    echo
    echo ">>> Processing commit to branch '${branch}' <<<"
    echo

    echo "--> updating cache..."
    cd /var/cache/puppet-git
    git fetch

    cd /etc/puppet/environments

    # if there's just an empty directory, try to get it out of the way
    rmdir $branch 2>/dev/null

    if [ -e $branch -a ! -f ${branch}/.git/HEAD ]; then
        echo "FATAL: /etc/puppet/environments/${branch} exists but is invalid"
        exit 1
    fi

    if [ ! -e $branch ]; then
        # the following is based on git-new-workdir from the contrib
        # directory of the git source

        echo "--> creating new Puppet environment '${branch}'..."
        mkdir -p ${branch}/.git
        cd $branch
        for x in config refs logs/refs objects info hooks packed-refs remotes rr-cache svn
        do
             case $x in
             */*)
                 mkdir -p $(dirname .git/$x)
                 ;;
             esac
             ln -s /var/cache/puppet-git/.git/$x .git/$x
        done
        cp /var/cache/puppet-git/.git/HEAD .git/HEAD
        git checkout -f $branch

        echo "--> setting up shared librarian-puppet cache..."
        mkdir -p /var/cache/librarian-puppet
        ln -sf /var/cache/librarian-puppet .tmp
    else
        echo "--> updating existing Puppet environment '${branch}'..."
        cd $branch
        git merge origin/${branch}
    fi

    echo "--> running librarian-puppet..."
    librarian-puppet install --use-v1-api

    echo "--> Fixing permissions..."
    find /etc/puppet/environments/${branch} -type d -exec chmod 02775 {} \; 2>/dev/null
    find /etc/puppet/environments/${branch} -type f -exec chmod 0664 {} \; 2>/dev/null

    echo
done
EOF
chmod 0755 /srv/puppet.git/hooks/post-receive

log "Configuring Hiera"
gem install --no-rdoc --no-ri deep_merge
cat > /etc/puppet/hiera.yaml <<'EOF'
---
:backends:
  - consul
  - yaml
  - module_data

:hierarchy:
  - "fqdn/%{::fqdn}"
  - "nodes/%{::fqdn}"
  - "osfamily/%{::osfamily}"
  - "locations/%{::location}"
  - "common"

:yaml:
  :datadir: "/etc/puppet/environments/%{::environment}/hieradata"

:consul:
  :paths:
    - "kv/nodes/%{::domain}/%{::hostname}"
    - "kv/osfamily/%{::osfamily}"
    - "kv/locations/%{::location}"
    - "kv/common"
EOF
ln -sf /etc/puppet/hiera.yaml /etc/hiera.yaml

log "Deploying initial cofiguration to 'boostrap' Puppet environment"
git clone /srv/puppet.git /tmp/bootstrap
cd /tmp/bootstrap
mkdir -p -m 02775 modules manifests hieradata/{nodes,locations}

cat > manifests/site.pp <<EOF
include puppetdb
include puppetdb::master::config
EOF

cat > Puppetfile <<EOF
forge 'https://forgeapi.puppetlabs.com/'

mod 'puppetlabs/puppetdb'
mod 'mmickan/hiera_consul', :git => 'https://github.com/mmickan/hiera-consul'
mod 'ripienaar/module_data'
EOF

git add .
git config --global user.name 'Puppetmaster Bootstrap'
git config --global user.email mark.mickan@articul-8.com
git commit -a -m 'Puppetmaster bootstrap'
git push origin HEAD:bootstrap

# prepare for the puppetlabs postgresql module to get things wrong, and work
# around it
mkdir -p /etc/postgresql
ln -sf /etc/postgresql /etc/postgresql/9.3
mkdir -p /var/lib/postgresql
ln -sf /var/lib/postgresql /var/lib/postgresql/9.3

log "Reloading puppetmaster configuration"
/etc/init.d/puppetmaster restart

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

log "Running puppet agent"
puppet agent -t --environment bootstrap

log "Puppet agent returned '$?'"

log "Running puppet agent again to check for idempotency"
puppet agent -t --environment bootstrap

status=$?
log "Puppet agent returned '$status'"

if [ $status -eq 0 ]; then
    log "Configuring puppet service in Consul"
    cat >/etc/consul.d/puppet.json <<EOF
    {
        "service": {
            "name": "puppet",
            "port": 8140,
            "check": {
                "id": "service:puppet",
                "name": "Puppet master HTTPS",
                "script": "wget -q -O- --header='Accept: pson' --ca-certificate=/var/lib/puppet/ssl/certs/ca.pem --certificate=/var/lib/puppet/ssl/certs/$(hostname -f).pem --private-key=/var/lib/puppet/ssl/private_keys/$(hostname -f).pem https://$(hostname -f):8140/production/status/test | grep -q '\"is_alive\":true' || bash -c 'exit 2'",
                "interval": "1m"
            }
        }
    }
EOF
    service consul reload
else
    # if we can't verify that it worked locally, then we don't want to
    # advertise to the rest of the environment that puppetmaster is ready to
    # accept work.  Better to let the deployment script time out waiting for
    # the signal, then destroy the VM and try again.
    warn "Puppet agent returned non-zero, skipping setup of puppetmaster service check"
fi

#
# At this point, you should now be able to succesfully run the following
# tests on puppetdb and hiera:
#
#  puppetdb:
#    $ sudo puppet node status $(hostname -f)
#    $ sudo puppet node find $(hostname -f) | python -mjson.tool
#
#  hiera:
#    $ hiera -a classes ::environment=bootstrap ::fqdn=$(hostname -f)
#
# ...and puppet.service.<dc>.<domain> will resolve when the puppetmaster is available.
#
