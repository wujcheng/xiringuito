#!/usr/bin/env bash
#
# Setup server before establishing connection
#
set -e

if [[ ${#} != 2 ]]; then
  echo "Usage: ${0} TUNNEL_ID IP_BASE"
  exit 1
fi

declare -r TUNNEL_ID=${1}
declare -r IP_BASE=${2}

declare -r NETWORK_DEVICE=tun${TUNNEL_ID}
let CLIENT_LAST_IP_ADDR_OCTET="4*(${TUNNEL_ID}-1)+1"
let SERVER_LAST_IP_ADDR_OCTET="4*(${TUNNEL_ID}-1)+2"
declare -r CLIENT_IP_ADDR=${IP_BASE}.${CLIENT_LAST_IP_ADDR_OCTET}
declare -r SERVER_IP_ADDR=${IP_BASE}.${SERVER_LAST_IP_ADDR_OCTET}

declare -r SSHD_CONFIG_FILE=/etc/ssh/sshd_config
declare -r SSHD_RESTART_CMD="reload ssh"

# Ensure previous tunnels with the same ID are not running
set +e
pkill -f xiringuito-server-execute.${TUNNEL_ID}.sh
set -e

# Set up network device
if [[ ! $(ip link | grep " ${NETWORK_DEVICE}: ") ]]; then
  sudo modprobe tun
  sudo ip tuntap add mode tun user ${USER} ${NETWORK_DEVICE}
  sudo ip link set ${NETWORK_DEVICE} up
  sudo ip addr add ${SERVER_IP_ADDR}/30 dev ${NETWORK_DEVICE}
fi

# Set up SSH server for tunneling
if [[ ! $(grep "^PermitTunnel yes" ${SSHD_CONFIG_FILE}) ]]; then
  echo "PermitTunnel yes" | sudo tee -a ${SSHD_CONFIG_FILE}
  sudo ${SSHD_RESTART_CMD}
fi

# We need IPv4 forwarding to enable packet traversal
if [[ ! $(sudo sysctl -a 2>/dev/null | grep "net.ipv4.ip_forward.*=.*1") ]]; then
  sudo sysctl -w net.ipv4.ip_forward=1
fi

# We need IPv4 NAT
if [[ ! $(sudo iptables -t nat -nvL POSTROUTING | grep " ${CLIENT_IP_ADDR} ") ]]; then
  sudo iptables -t nat -A POSTROUTING -s ${CLIENT_IP_ADDR} -j MASQUERADE
fi
