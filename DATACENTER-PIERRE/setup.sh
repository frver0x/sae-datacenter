#!/bin/bash
# setup.sh — bootstrap + deploy sur Debian nue
# Usage: bash setup.sh fabric   (VM222 — topo-ebgp + EVPN)
#        bash setup.sh bench    (VM223 — 4 topos + benchmark)
set -euo pipefail

ROLE="${1:-}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAB_VERSION="0.76.1"
FRR_IMAGE="quay.io/frrouting/frr:10.6.1"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
log() { echo -e "${BLUE}[setup]${NC} $*"; }
ok()  { echo -e "${GREEN}[ok]${NC} $*"; }
err() { echo -e "${RED}[err]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]]                                   && err "Run as root"
[[ "$ROLE" != "fabric" && "$ROLE" != "bench" ]]     && err "Usage: $0 fabric|bench"

log "Role: $ROLE | Repo: $REPO_DIR"

# ── 1. Deps ──────────────────────────────────────────────────────────────────
log "apt update + deps..."
apt-get update -qq
apt-get install -y -qq curl ca-certificates gnupg python3 git

# ── 2. Docker ─────────────────────────────────────────────────────────────────
if command -v docker &>/dev/null; then
    ok "Docker $(docker --version | awk '{print $3}' | tr -d ',')"
else
    log "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    ok "Docker installed"
fi

# ── 3. containerlab ───────────────────────────────────────────────────────────
if command -v containerlab &>/dev/null; then
    ok "containerlab $(containerlab version 2>/dev/null | awk '/version/{print $2}' | head -1)"
else
    log "Installing containerlab ${CLAB_VERSION}..."
    curl -sL https://containerlab.dev/setup | bash -s "${CLAB_VERSION}"
    ok "containerlab installed"
fi

# ── 4. Images ─────────────────────────────────────────────────────────────────
log "Pulling images..."
docker pull "$FRR_IMAGE"
docker pull alpine:latest
ok "Images ready"

# ── 5. Role ───────────────────────────────────────────────────────────────────
if [[ "$ROLE" == "fabric" ]]; then
    log "Deploying topo-ebgp (eBGP + VXLAN + EVPN inter-DC)..."
    cd "${REPO_DIR}/containerlab/topo-ebgp"
    containerlab deploy -t topology.clab.yml
    ok "Fabric deployed"

    log "Waiting 25s for BGP convergence..."
    sleep 25
    echo ""
    echo "── BGP summary spine1 ──"
    docker exec clab-topo-ebgp-spine1 vtysh -c "show bgp summary" 2>/dev/null || true
    echo ""
    echo "── Commandes utiles ──"
    echo "  containerlab inspect --all"
    echo "  docker exec clab-topo-ebgp-spine1 vtysh -c 'show bgp summary'"
    echo "  docker exec clab-topo-ebgp-bleaf vtysh -c 'show bgp l2vpn evpn summary'"

elif [[ "$ROLE" == "bench" ]]; then
    log "Setup bench (4 topos routing)..."
    for TOPO in topo-ebgp topo-ibgp-rr topo-ospf topo-mixed; do
        ln -sfn "${REPO_DIR}/containerlab/${TOPO}" "/root/${TOPO}"
        ok "Symlink /root/${TOPO} → ${REPO_DIR}/containerlab/${TOPO}"
    done
    ln -sfn "${REPO_DIR}/containerlab/benchmark.sh" "/root/benchmark.sh"
    ok "Symlinks créés dans /root/"
    echo ""
    echo "Lance le benchmark : bash /root/benchmark.sh"
    echo "Résultats JSON     : /root/results/"
fi

echo ""
ok "Done (role=$ROLE)"
