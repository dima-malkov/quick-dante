#!/bin/env bash

# Proxy port. Third argument or default value.
PORT=${3:-"5678"}

if [ ! $1 ] || [ ! $2 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]
then
	echo "Usage: $0 user password [port] ['orig']"
	exit 1
fi

USER=$1
PASSWORD=$2

DANTE_CONFIG=$(cat <<EOF
logoutput: syslog
user.privileged: root
user.unprivileged: nobody

# The listening network interface or address.
internal: 0.0.0.0 port=$PORT

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

SYSCTL_CONF=$(cat <<'EOF'
net.ipv4.ip_default_ttl = 128
net.ipv4.route.min_adv_mss = 1460
net.ipv4.tcp_rmem = 8192 87380 4194304
net.ipv4.tcp_wmem = 8192 87380 4194304

net.ipv4.tcp_timestamps=0
net.ipv4.tcp_window_scaling=0
EOF
)

echo "Installing dante-server..."
sudo apt update > /dev/null
sudo apt install dante-server > /dev/null

echo "Updating config files..."
sudo mv /etc/danted.conf /etc/danted.conf.orig
sudo bash -c  "echo \"$DANTE_CONFIG\" > /etc/danted.conf"

echo "Adding user $USER..."
sudo useradd -r -s /bin/false $USER
echo "$USER:$PASSWORD" | sudo chpasswd

echo "Restarting Dante..."
sudo systemctl restart danted.service
sudo systemctl status | fgrep "Active:"

if [ "$4" != "orig" ]
then
	echo "Setting up Windows TCP fingerprint..."
	sudo bash -c "echo \"$SYSCTL_CONF\" > /etc/sysctl.d/01-win-finger.conf"
	sudo sysctl -p /etc/sysctl.d/01-win-finger.conf > /dev/null
fi

echo "DONE"
