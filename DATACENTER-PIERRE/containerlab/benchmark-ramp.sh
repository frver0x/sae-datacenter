#!/bin/bash
# Rampe de charge : trouve le point de saturation de chaque topo.
# UDP à débit offert croissant -> mesure reçu + loss%. Le genou de la courbe = sature.
# Usage: bash benchmark-ramp.sh [topo1 topo2 ...]   (defaut: les 4 routing)
set -e

TOPOS=("${@:-topo-ebgp topo-ibgp-rr topo-ospf topo-mixed}")
# si passe en 1 seul arg "a b c", re-split
TOPOS=(${TOPOS[@]})

RESULTS=/root/results/ramp
STEPS_GBPS=(1 2 4 6 8 10 12 14 16 18 20 25 30)   # paliers offered load
DUR=10                                            # s par palier
DPORT=192.168.3.2

mkdir -p "$RESULTS"

for TOPO in "${TOPOS[@]}"; do
  echo "════════ $TOPO ════════"
  cd /root/$TOPO
  containerlab deploy -t topology.clab.yml --reconfigure
  echo "  ⏳ 35s convergence..."
  sleep 35

  SERVER="clab-${TOPO}-host3"
  CLIENT="clab-${TOPO}-host1"
  docker exec $SERVER which iperf3 >/dev/null 2>&1 || docker exec $SERVER apk add --no-cache iperf3
  docker exec $CLIENT which iperf3 >/dev/null 2>&1 || docker exec $CLIENT apk add --no-cache iperf3
  docker exec -d $SERVER iperf3 -s
  sleep 2

  CSV="$RESULTS/${TOPO}.csv"
  echo "offered_gbps,recv_gbps,loss_pct,recv_pps" > "$CSV"

  for G in "${STEPS_GBPS[@]}"; do
    echo "  ▶ offered ${G}G ..."
    J=$(docker exec $CLIENT iperf3 -c $DPORT -u -b ${G}G -t $DUR -J 2>/dev/null) || { echo "  ✗ palier ${G}G échoué (decroche)"; echo "${G},0,100,0" >> "$CSV"; continue; }
    echo "$J" | python3 -c "
import json,sys
d=json.load(sys.stdin)
s=d['end']['sum']
recv=s['bits_per_second']/1e9
loss=s.get('lost_percent',0)
pps=s['packets']/s['seconds'] if s.get('seconds') else 0
print(f\"$G,{recv:.2f},{loss:.2f},{int(pps)}\")
" >> "$CSV"
  done

  echo "  ✓ $TOPO -> $CSV"
  cat "$CSV"
  containerlab destroy -t topology.clab.yml --cleanup
  sleep 5
done

echo ""
echo "CSV dans $RESULTS/  — plot: python3 /root/plot-ramp.py"
