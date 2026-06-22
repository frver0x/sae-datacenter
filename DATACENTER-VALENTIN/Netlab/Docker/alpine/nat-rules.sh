#!/bin/bash
# nat-rules.sh
set -e

EXT_IF="${EXT_IF:-eth0}"
INT_IF="${INT_IF:-eth1}"
EXT_IP="${EXT_IP:-10.202.8.205}"
INT_SNAT_NET="${INT_SNAT_NET:-172.16.1.0/24}"
BLEAF_TRANSIT="10.202.9.0/30"

echo "[nat-rules] Attente de l'interface ${EXT_IF}..."
for i in $(seq 1 30); do
  if ip link show "${EXT_IF}" >/dev/null 2>&1; then
    echo "[nat-rules] ${EXT_IF} trouvée"
    break
  fi
  sleep 1
done

echo "[nat-rules] Attente de l'interface ${INT_IF}..."
for i in $(seq 1 30); do
  if ip link show "${INT_IF}" >/dev/null 2>&1; then
    echo "[nat-rules] ${INT_IF} trouvée"
    break
  fi
  sleep 1
done

echo "[nat-rules] Activation IP forwarding"
sysctl -w net.ipv4.ip_forward=1

echo "[nat-rules] Remplacement de la route par défaut vers la salle"
ip route del default 2>/dev/null || true
ip route add default via 10.202.255.254 dev "${EXT_IF}" 2>/dev/null || echo "[nat-rules] WARNING: impossible d'ajouter la route par défaut"

echo "[nat-rules] Flush des règles existantes"
iptables -F
iptables -t nat -F
iptables -X

echo "[nat-rules] Politique par défaut"
iptables -P FORWARD DROP
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# --- SNAT overload : VLAN web (172.16.1.0/24) ---
echo "[nat-rules] SNAT overload ${INT_SNAT_NET} -> ${EXT_IP}"
iptables -t nat -A POSTROUTING -s "${INT_SNAT_NET}" -o "${EXT_IF}" -j SNAT --to-source "${EXT_IP}"
iptables -A FORWARD -s "${INT_SNAT_NET}" -o "${EXT_IF}" -j ACCEPT

# --- SNAT overload : transit bleaf <-> alpine_nat (10.202.9.0/30) ---
echo "[nat-rules] SNAT transit ${BLEAF_TRANSIT} -> ${EXT_IP}"
iptables -t nat -A POSTROUTING -s "${BLEAF_TRANSIT}" -o "${EXT_IF}" -j SNAT --to-source "${EXT_IP}"
iptables -A FORWARD -s "${BLEAF_TRANSIT}" -o "${EXT_IF}" -j ACCEPT

# --- DNAT 1:1 ---
declare -A NAT_MAP=(
  ["10.202.8.210"]="172.16.1.1"
  ["10.202.8.211"]="172.16.1.2"
  ["10.202.8.212"]="172.16.1.3"
)

for PUB_IP in "${!NAT_MAP[@]}"; do
  PRIV_IP="${NAT_MAP[$PUB_IP]}"
  echo "[nat-rules] NAT 1:1 ${PUB_IP} <-> ${PRIV_IP}"
  iptables -t nat -A PREROUTING -i "${EXT_IF}" -d "${PUB_IP}" -j DNAT --to-destination "${PRIV_IP}"
  iptables -t nat -A POSTROUTING -o "${EXT_IF}" -s "${PRIV_IP}" -j SNAT --to-source "${PUB_IP}"
  iptables -A FORWARD -d "${PRIV_IP}" -i "${EXT_IF}" -o "${INT_IF}" -j ACCEPT
  iptables -A FORWARD -s "${PRIV_IP}" -i "${INT_IF}" -o "${EXT_IF}" -j ACCEPT
done

echo "[nat-rules] Règles appliquées :"
iptables -t nat -L -n -v