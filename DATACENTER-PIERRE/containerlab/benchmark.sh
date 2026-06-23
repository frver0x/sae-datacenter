#!/bin/bash
set -e

TOPOS=("topo-ebgp" "topo-ibgp-rr" "topo-ospf" "topo-mixed")
RESULTS=/root/results

mkdir -p $RESULTS

for TOPO in "${TOPOS[@]}"; do
  echo ""
  echo "════════════════════════════════════════════"
  echo "  ▶ $TOPO"
  echo "════════════════════════════════════════════"

  cd /root/$TOPO
  containerlab deploy -t topology.clab.yml --reconfigure

  echo "  ⏳ Waiting 35s for routing convergence..."
  sleep 35

  SERVER="clab-${TOPO}-host3"
  CLIENT="clab-${TOPO}-host1"

  # Ensure iperf3 available
  docker exec $SERVER which iperf3 > /dev/null 2>&1 || docker exec $SERVER apk add --no-cache iperf3
  docker exec $CLIENT  which iperf3 > /dev/null 2>&1 || docker exec $CLIENT  apk add --no-cache iperf3

  # Start server daemon
  docker exec -d $SERVER iperf3 -s
  sleep 2

  echo "  ▶ TCP 30s..."
  docker exec $CLIENT iperf3 -c 192.168.3.2 -t 30 -J \
    > $RESULTS/${TOPO}-tcp.json 2>&1

  echo "  ▶ UDP 10G 30s..."
  docker exec $CLIENT iperf3 -c 192.168.3.2 -t 30 -u -b 10G -J \
    > $RESULTS/${TOPO}-udp.json 2>&1

  echo "  ✓ $TOPO done"
  containerlab destroy -t topology.clab.yml --cleanup
  sleep 5
done

echo ""
echo "════════════════════════════════════════════"
echo "  RESULTS"
echo "════════════════════════════════════════════"
for TOPO in "${TOPOS[@]}"; do
  TCP=$(python3 -c "
import json
d = json.load(open('$RESULTS/${TOPO}-tcp.json'))
print(round(d['end']['sum_received']['bits_per_second']/1e9, 2))
" 2>/dev/null || echo "N/A")
  UDP=$(python3 -c "
import json
d = json.load(open('$RESULTS/${TOPO}-udp.json'))
print(round(d['end']['sum']['bits_per_second']/1e9, 2))
" 2>/dev/null || echo "N/A")
  printf "  %-15s  TCP: %6s Gbit/s  |  UDP: %6s Gbit/s\n" "$TOPO" "$TCP" "$UDP"
done
echo ""
