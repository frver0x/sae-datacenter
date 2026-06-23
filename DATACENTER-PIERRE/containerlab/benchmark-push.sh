#!/bin/bash
# Benchmark stabilité 4 protocoles — TCP retransmits + UDP loss% + jitter + sweep saturation.
# Pousse les métriques vers Pushgateway -> Prometheus -> Grafana (dashboard sae4d01-lab221).
#
# IMPORTANT (fix 2026-06-22) : chaque palier du sweep est poussé dans SON PROPRE groupe
# Pushgateway (.../target/<n>g). Sans ça, tous les paliers partagent le même groupe
# {job,topo} et s'écrasent l'un l'autre -> seul le dernier palier survit (bug "mixed @ 80G = 0").
set -u

TOPOS=("topo-ebgp" "topo-ibgp-rr" "topo-ospf" "topo-mixed")
RESULTS=/root/results
PUSHGW="http://localhost:9091"
# Paliers UDP pour test saturation (bps)
SWEEP_TARGETS="5000000000 10000000000 20000000000 40000000000 80000000000"
mkdir -p "$RESULTS"

# bps entier -> Gbit/s entier (label/URL)
gbps() { awk -v b="$1" 'BEGIN{printf "%.0f", b/1e9}'; }

push_all() {
  local topo=$1 tcp_bps=$2 tcp_retransmits=$3 udp_bps=$4 udp_lost_pct=$5 udp_jitter_ms=$6
  printf '# TYPE iperf3_tcp_bps gauge
iperf3_tcp_bps{topo="%s"} %s
# TYPE iperf3_tcp_retransmits gauge
iperf3_tcp_retransmits{topo="%s"} %s
# TYPE iperf3_udp_bps gauge
iperf3_udp_bps{topo="%s"} %s
# TYPE iperf3_udp_lost_pct gauge
iperf3_udp_lost_pct{topo="%s"} %s
# TYPE iperf3_udp_jitter_ms gauge
iperf3_udp_jitter_ms{topo="%s"} %s
' "$topo" "$tcp_bps" "$topo" "$tcp_retransmits" "$topo" "$udp_bps" \
  "$topo" "$udp_lost_pct" "$topo" "$udp_jitter_ms" \
  | curl -s --data-binary @- "${PUSHGW}/metrics/job/iperf3/topo/${topo}"
}

push_sweep() {
  local topo=$1 target_bps=$2 lost_pct=$3 actual_bps=$4
  local tg; tg=$(gbps "$target_bps")
  # un groupe par palier : /target/<n>g  (sinon les paliers s'écrasent)
  printf '# TYPE iperf3_sweep_lost_pct gauge
iperf3_sweep_lost_pct{topo="%s",target_gbps="%s"} %s
# TYPE iperf3_sweep_actual_bps gauge
iperf3_sweep_actual_bps{topo="%s",target_gbps="%s"} %s
' "$topo" "$tg" "$lost_pct" "$topo" "$tg" "$actual_bps" \
  | curl -s --data-binary @- "${PUSHGW}/metrics/job/iperf3_sweep/topo/${topo}/target/${tg}g"
}

# (re)démarre un serveur iperf3 sain dans le conteneur host3
ensure_server() {
  local srv=$1
  docker exec "$srv" pgrep -x iperf3 >/dev/null 2>&1 && return 0
  docker exec -d "$srv" iperf3 -s -D; sleep 1
}

jq_field() {  # fichier, chemin python -> valeur ou défaut
  python3 -c "import json;d=json.load(open('$1'));print($2)" 2>/dev/null || echo "$3"
}

for TOPO in "${TOPOS[@]}"; do
  echo ""; echo "==================== $TOPO ===================="
  cd "/root/$TOPO" || continue
  containerlab deploy -t topology.clab.yml --reconfigure >/dev/null 2>&1
  echo "  convergence 35s..."; sleep 35

  SERVER="clab-${TOPO}-host3"; CLIENT="clab-${TOPO}-host1"

  # ECMP hash L4 sur les leaves (répartition sur les 2 spines)
  for c in $(docker ps --format '{{.Names}}' | grep "clab-${TOPO}-leaf"); do
    docker exec "$c" sysctl -w net.ipv4.fib_multipath_hash_policy=1 >/dev/null 2>&1
  done

  docker exec "$SERVER" which iperf3 >/dev/null 2>&1 || docker exec "$SERVER" apk add --no-cache iperf3 >/dev/null 2>&1
  docker exec "$CLIENT" which iperf3 >/dev/null 2>&1 || docker exec "$CLIENT" apk add --no-cache iperf3 >/dev/null 2>&1
  ensure_server "$SERVER"; sleep 1

  # TCP baseline (4 flux parallèles)
  echo "  TCP 30s (retransmits)"
  docker exec "$CLIENT" iperf3 -c 192.168.3.2 -t 30 -P 4 -J > "$RESULTS/${TOPO}-tcp.json" 2>&1

  # UDP 10G baseline (loss/jitter)
  echo "  UDP 10G 30s (loss/jitter)"
  docker exec "$CLIENT" iperf3 -c 192.168.3.2 -t 30 -u -b 10G -J > "$RESULTS/${TOPO}-udp.json" 2>&1

  TCP_BPS=$(jq_field "$RESULTS/${TOPO}-tcp.json" "int(d['end']['sum_received']['bits_per_second'])" 0)
  TCP_RTX=$(jq_field "$RESULTS/${TOPO}-tcp.json" "int(d['end']['sum_sent']['retransmits'])" 0)
  UDP_BPS=$(jq_field "$RESULTS/${TOPO}-udp.json" "int(d['end']['sum']['bits_per_second'])" 0)
  UDP_LOST=$(jq_field "$RESULTS/${TOPO}-udp.json" "round(d['end']['sum']['lost_percent'],2)" 0)
  UDP_JITTER=$(jq_field "$RESULTS/${TOPO}-udp.json" "round(d['end']['sum']['jitter_ms'],3)" 0)

  push_all "$TOPO" "$TCP_BPS" "$TCP_RTX" "$UDP_BPS" "$UDP_LOST" "$UDP_JITTER"
  echo "  TCP: $(awk -v b="$TCP_BPS" 'BEGIN{printf "%.2f",b/1e9}') Gbit/s  RTX=$TCP_RTX"
  echo "  UDP: $(awk -v b="$UDP_BPS" 'BEGIN{printf "%.2f",b/1e9}') Gbit/s  Loss=${UDP_LOST}%  Jitter=${UDP_JITTER}ms"

  # Sweep saturation — 1 groupe Pushgateway par palier, retry 1x si tir raté
  echo "  Sweep saturation UDP..."
  for TARGET in $SWEEP_TARGETS; do
    TGBPS=$(gbps "$TARGET")
    OUT="$RESULTS/${TOPO}-sweep-${TGBPS}g.json"
    S_BPS=0; S_LOST=100
    for attempt in 1 2; do
      ensure_server "$SERVER"
      docker exec "$CLIENT" iperf3 -c 192.168.3.2 -t 15 -u -b "${TARGET}" -J > "$OUT" 2>&1
      S_LOST=$(jq_field "$OUT" "round(d['end']['sum']['lost_percent'],2)" 100)
      S_BPS=$(jq_field "$OUT" "int(d['end']['sum']['bits_per_second'])" 0)
      [ "$S_BPS" != "0" ] && break
      echo "    ${TGBPS}G tir raté (tentative ${attempt}) — restart serveur + retry"
      docker exec "$SERVER" pkill iperf3 2>/dev/null; sleep 2
    done
    push_sweep "$TOPO" "$TARGET" "$S_LOST" "$S_BPS"
    echo "    ${TGBPS}G → $(awk -v b="$S_BPS" 'BEGIN{printf "%.1f",b/1e9}') Gbit/s  loss=${S_LOST}%"
  done

  containerlab destroy -t topology.clab.yml --cleanup >/dev/null 2>&1; sleep 5
done

echo ""; echo "Done — résultats dans Grafana http://localhost:3000 (dashboard sae4d01-lab221)"
