#!/usr/bin/env bash
# Forward TCP 8443, 51514, 51515 arriving on this host to 10.0.230.50 (same ports).
# Usage: sudo ./port-forward.sh [add|remove]   (default: add)
set -euo pipefail

TARGET=10.0.230.50
PORTS=(8443 51514 51515)
ACTION=${1:-add}

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }

rule() { # $1 = -C/-A/-D, remaining args = rule spec
  local op=$1; shift
  if [[ $op == -A ]]; then
    iptables -C "$@" 2>/dev/null || iptables -A "$@"
  else
    iptables -D "$@" 2>/dev/null || true
  fi
}

op=-A; [[ $ACTION == remove ]] && op=-D

if [[ $ACTION == add ]]; then
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-port-forward.conf
fi

for p in "${PORTS[@]}"; do
  rule $op PREROUTING -t nat -p tcp --dport "$p" -j DNAT --to-destination "$TARGET:$p"
  rule $op OUTPUT     -t nat -p tcp -o lo --dport "$p" -j DNAT --to-destination "$TARGET:$p"
  rule $op FORWARD    -p tcp -d "$TARGET" --dport "$p" -j ACCEPT
  rule $op FORWARD    -p tcp -s "$TARGET" --sport "$p" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
done
# Masquerade so replies from the target come back through this host
rule $op POSTROUTING -t nat -p tcp -d "$TARGET" -m multiport --dports "$(IFS=,; echo "${PORTS[*]}")" -j MASQUERADE

echo "Done ($ACTION). Current NAT rules:"
iptables -t nat -S | grep -E "$TARGET" || true
echo "To persist across reboots: apt install iptables-persistent && netfilter-persistent save"
