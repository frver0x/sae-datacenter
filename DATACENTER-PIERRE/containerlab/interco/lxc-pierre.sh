#!/usr/bin/env bash
# lxc-pierre.sh — attache un conteneur hôte "lxc-pierre" dans le VLAN 570 (VNI 570100)
# de la fabric topo-ebgp, sur le bridge VTEP br-val2 du border-leaf. L'hôte obtient une IP
# dans le sous-réseau L2 partagé inter-DC (172.16.31.0/24) ; le fabric Arista de Valentin
# le voit alors comme un hôte local du VLAN et peut le pinguer via EVPN/VXLAN.
#
# Idempotent : relançable sans casser l'existant. Ne redéploie PAS la fabric (non disruptif).
#   Usage : sudo bash lxc-pierre.sh           (up,  IP 172.16.31.10)
#           sudo bash lxc-pierre.sh down      (supprime conteneur + veth)
set -euo pipefail

NODE="lxc-pierre"
IMG="alpine:latest"
LAB_BLEAF="clab-topo-ebgp-bleaf"
BRIDGE="br-val2"           # bridge VTEP du VNI 570100 dans le netns de bleaf
HOST_IP="172.16.31.10/24"  # IP de l'hôte dans le VLAN 570 inter-DC
GW="172.16.31.254"         # passerelle anycast du VLAN 570
MTU=1450                   # overhead VXLAN
VETH_C="lxcp-c"            # extrémité côté conteneur
VETH_B="lxcp-b"            # extrémité côté bleaf (br-val2)

die() { echo "[lxc-pierre] ERREUR: $*" >&2; exit 1; }
log() { echo "[lxc-pierre] $*"; }

if [[ "${1:-up}" == "down" ]]; then
  docker rm -f "$NODE" 2>/dev/null && log "conteneur $NODE supprimé" || true
  ip link del "$VETH_B" 2>/dev/null || true
  log "down terminé"; exit 0
fi

command -v docker  >/dev/null || die "docker absent"
command -v nsenter >/dev/null || die "nsenter absent"
docker inspect "$LAB_BLEAF" >/dev/null 2>&1 || die "$LAB_BLEAF introuvable (fabric topo-ebgp non déployée ?)"

BLEAFPID=$(docker inspect -f '{{.State.Pid}}' "$LAB_BLEAF")
nsenter -t "$BLEAFPID" -n ip link show "$BRIDGE" >/dev/null 2>&1 || die "bridge $BRIDGE absent dans bleaf"

# 1. conteneur hôte (réseau none : on câble nous-mêmes le veth dans le VLAN)
if ! docker inspect "$NODE" >/dev/null 2>&1; then
  log "création du conteneur $NODE..."
  docker run -d --name "$NODE" --network none --cap-add NET_ADMIN \
    "$IMG" sleep infinity >/dev/null
fi
LXCPID=$(docker inspect -f '{{.State.Pid}}' "$NODE")

# 2. veth : une extrémité dans bleaf (master br-val2), l'autre dans le conteneur
if ! nsenter -t "$LXCPID" -n ip link show eth1 >/dev/null 2>&1; then
  ip link del "$VETH_B" 2>/dev/null || true
  ip link add "$VETH_C" type veth peer name "$VETH_B"
  ip link set "$VETH_B" netns "$BLEAFPID"
  ip link set "$VETH_C" netns "$LXCPID"
  nsenter -t "$BLEAFPID" -n ip link set "$VETH_B" master "$BRIDGE" mtu "$MTU" up
  nsenter -t "$LXCPID"   -n ip link set "$VETH_C" name eth1
fi

# 3. adressage côté conteneur (idempotent)
nsenter -t "$LXCPID" -n ip link set eth1 mtu "$MTU" up
nsenter -t "$LXCPID" -n sh -c "ip addr show dev eth1 | grep -q '${HOST_IP%/*}' || ip addr add $HOST_IP dev eth1"
nsenter -t "$LXCPID" -n ip route replace default via "$GW" 2>/dev/null || true

log "OK — $NODE @ ${HOST_IP%/*} sur VLAN 570 (VNI 570100), GW $GW"
nsenter -t "$LXCPID" -n ip -br addr show eth1
