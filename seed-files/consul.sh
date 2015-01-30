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

# consul version (only used if downloading Hashicorp's zip distribution)
VERSION=0.4.1

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
        curl -s -k -L -o /tmp/consul_$ZIP $URL || {
            log "Unable to download Consul"
            exit 1
        }

        unzip -qq /tmp/consul_${ZIP} -d /usr/bin/
        rm -f /tmp/consul_${ZIP}

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

[ -f /etc/sysconfig/consul ] && . /etc/sysconfig/consul
[ -f /etc/default/consul ] && . /etc/default/consul

RETVAL=0
prog="consul"
CONSUL="/usr/bin/consul"

start()
{
    # Make sure to use all our CPUs, because Consul can block a scheduler thread
    export GOMAXPROCS=`nproc`

    # Get the public IP of the first ethernet interface
    BIND=`ifconfig eth0 | grep "inet addr" | awk '{ print substr($2,6) }'`

    [ -x $CONSUL ] || exit 5
    [ -d /etc/consul.d ] || exit 6

    echo -n $"Starting $prog: "
    $CONSUL agent -config-dir="/etc/consul.d" -bind=$BIND ${CONSUL_FLAGS} >/dev/null 2>&1 &
    echo $"[ OK ]"
    return $RETVAL
}

stop()
{
    echo -n $"Stopping $prog: "
    $CONSUL leave >/dev/null 2>&1
    echo $"[ OK ]"
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

        cat > /etc/consul.d/20-agent.json <<'EOF'
{
  "data_dir": "/var/lib/consul"
}
EOF

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
