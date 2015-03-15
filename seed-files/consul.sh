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

# consul version (only used if downloading Hashicorp's zip distribution)
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
    if [ -e /usr/bin/apt-get ]; then
        log "Installing Consul from bcandrea/consul PPA"
        apt-add-repository -y ppa:bcandrea/consul
        apt-get update
        apt-get install -y consul consul-web-ui

    # otherwise, try to do it the hard way
    elif [ -e /usr/bin/unzip -a -e /usr/bin/curl ]; then
        log "Installing Consul version ${VERSION}"
        ARCH=`uname -m`
        case "${ARCH}" in
            i386)
                ZIP="${VERSION}_linux_386.zip"
                ;;
            x86_64)
                ZIP="${VERSION}_linux_amd64.zip"
                ;;
            *)
                log "Unable to install Consul (unknown arch ${ARCH})"
                exit 1
                ;;
        esac

        URL="https://dl.bintray.com/mitchellh/consul/${ZIP}"
        mkdir -p /opt/staging/consul
        curl -s -k -L -o /opt/staging/consul/consul.zip $URL || {
            log "Unable to download Consul"
            exit 1
        }

        unzip -qq /opt/staging/consul/consul.zip -d /usr/bin/
        # leave this file in place so puppet doesn't re-download/re-install
        #rm -f /opt/staging/consul/consul.zip

        cat > /etc/init.d/consul <<'EOF'
#!/bin/bash
#
# consul            Start up the Consul agent
#
# chkconfig: 2345 55 25
# description: Consul is service discovery and configuration made easy. \
#              This service starts up the Consul agent.
#

. /etc/rc.d/init.d/functions

CONSUL=/usr/bin/consul
CONFIG=/etc/consul.d
PID_FILE=/var/run/consul/pidfile
LOG_FILE=/var/log/consul

[ -f /etc/sysconfig/consul ] && . /etc/sysconfig/consul
[ -f /etc/default/consul ] && . /etc/default/consul

RETVAL=0
prog="consul"

start()
{
    # Make sure to use all our CPUs, because Consul can block a scheduler thread
    export GOMAXPROCS=`nproc`

    # Get the public IP of the first ethernet interface
    BIND=`ifconfig eth0 | grep "inet addr" | awk '{ print substr($2,6) }'`

    [ -x $CONSUL ] || exit 5
    [ -d $CONFIG ] || exit 6

    echo -n $"Starting $prog: "
    daemon --user=consul --pidfile="$PID_FILE" $CONSUL agent -config-dir="${CONFIG}" -bind=${BIND} ${CONSUL_FLAGS} >> "$LOG_FILE" 2>&1 &
    echo $"[ OK ]"
    retcode=$?
    touch /var/lock/subsys/consul
    return $retcode
}

stop()
{
    echo -n $"Stopping $prog: "
    $CONSUL leave

    retcode=$?
    rm -f /var/lock/subsys/consul
    echo $"[ OK ]"
    return $retcode
}

restart()
{
    stop
    start
}

reload()
{
    restart
}

force_reload()
{
    restart
}

status()
{
    consul members >/dev/null 2>&1
    return $?
}

case "$1" in
    start)
        status && exit 0
        start
        ;;
    stop)
        status || exit 0
        stop
        ;;
    restart)
        restart
        ;;
    reload|force-reload)
        reload
        ;;
    status)
        status
        RETVAL=$?
        if [ $RETVAL -eq 0 ]; then
            echo "$prog is running"
        else
            echo "$prog is stopped"
        fi
        ;;
    *)
        echo $"Usage: $0 {start|stop|restart|reload|force-reload|status}"
        RETVAL=2
esac
exit $RETVAL
EOF
        chmod 0755 /etc/init.d/consul
        chkconfig --add consul
        useradd --system -U consul
        mkdir -m 0750 /var/lib/consul
        chown consul:consul /var/lib/consul

        log "Starting Consul"
        service consul start
        # consul needs a moment to start up... the next script to run is
        # going to expect it to be ready to answer queries, so pause here
        sleep 2

    else
        log "Unable to install Consul (tools unavailable)"
        exit 1
    fi

else
    log "Restarting Consul"
    service consul restart
fi
