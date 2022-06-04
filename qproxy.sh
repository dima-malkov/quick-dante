#!/bin/env bash

SocksDefaultPort="5678"
HttpDefaultPort="5679"

InfoColor="32"
ErrorColor="31"
DoneColor="1;33"

function cecho ()
{
    echo -e "\e[$1m$2\e[0m"
}

function show_help ()
{
    cat <<EOF
Usage: $0 [options] user password

    -s          Install SOCKS proxy
    -t          Install HTTP proxy

    -S port     SOCKS proxy port
    -T port     HTTP proxy port

    -w          Emulate Windows TCP fingerprint

    -h          Show help
EOF
    exit 0
}

UseSocks=""
UseHttp=""
MaskFP=""

SocksPort=$SocksDefaultPort
HttpPort=$HttpDefaultPort

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

while getopts "h?stS:?T:?w" opt; do
  case "$opt" in
    h|\?) show_help ;;
    s)  UseSocks="yes" ;;
    t)  UseHttp="yes" ;;
    S)  SocksPort=$OPTARG ;;
    T)  HttpPort=$OPTARG ;;
    w) MaskFP="yes" ;;
  esac
done

shift $((OPTIND-1))


ProxyUser=$1
ProxyPassword=$2

if [ ! $ProxyUser ] || [ ! $ProxyPassword ]; then
    show_help
fi

if [ -z $UseSocks ] && [ -z $UseHttp ]; then
    cecho $ErrorColor "You have to specify the -s or -t option, then I'll do something for you"
    show_help
fi


DanteConfig=$(cat <<EOF
logoutput: syslog
user.privileged: root
user.unprivileged: nobody

# The listening network interface or address.
internal: 0.0.0.0 port=$SocksPort

# The proxying network interface or address.
external: eth0

# socks-rules determine what is proxied through the external interface.
socksmethod: username

# client-rules determine who can connect to the internal interface.
clientmethod: none

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
}
EOF
            )

SquidConfig=$(cat <<EOF

http_port $HttpPort

auth_param basic program /usr/lib/squid3/basic_ncsa_auth /etc/squid/passwords
auth_param basic realm proxy
acl authenticated proxy_auth REQUIRED

http_access allow authenticated
EOF
           )

SysctlConfig=$(cat <<'EOF'
net.ipv4.ip_default_ttl = 128
net.ipv4.route.min_adv_mss = 1460
net.ipv4.tcp_rmem = 8192 87380 4194304
net.ipv4.tcp_wmem = 8192 87380 4194304

net.ipv4.tcp_timestamps=0
net.ipv4.tcp_window_scaling=0
EOF
)

if [ $UseSocks ]; then
    cecho $InfoColor "Installing Dante..."
    sudo apt update
    sudo apt install dante-server

    cecho $InfoColor "Updating Dante config file..."
    sudo mv /etc/danted.conf /etc/danted.conf.orig
    sudo bash -c  "echo \"$DanteConfig\" > /etc/danted.conf"

    cecho $InfoColor "Adding system user $ProxyUser..."
    sudo useradd -r -s /bin/false $ProxyUser
    echo "$ProxyUser:$ProxyPassword" | sudo chpasswd

    cecho $InfoColor "Restarting Dante..."
    sudo systemctl restart danted.service
    sudo systemctl show danted.service | fgrep "ActiveState"
fi

if [ $UseHttp ]; then
    cecho $InfoColor "Installing Squid..."
    sudo apt install squid apache2-utils

    cecho $InfoColor "Updating Squid config file..."
    sudo bash -c "echo \"$SquidConfig\" >> /etc/squid/squid.conf"

    cecho $InfoColor "Adding Squid user $ProxyUser..."
    echo $ProxyPassword | sudo htpasswd -i -c /etc/squid/passwords $ProxyUser

    cecho $InfoColor "Restarting Squid..."
    sudo systemctl restart squid.service
    sudo systemctl show squid.service | fgrep "ActiveState"
fi

if [ $MaskFP ]; then
    cecho $InfoColor "Setting up Windows TCP fingerprint..."
    sudo bash -c "echo \"$SYSCTL_CONF\" > /etc/sysctl.d/01-win-finger.conf"
    sudo sysctl -p /etc/sysctl.d/01-win-finger.conf > /dev/null
fi

cecho $DoneColor "DONE"
