#!/bin/bash
# entrypoint.sh
set -e

echo "[entrypoint] Démarrage Alpine NAT gateway"
echo "[entrypoint] EXT_IF=${EXT_IF:-eth0} INT_IF=${INT_IF:-eth1}"

/nat-rules.sh

echo "[entrypoint] Prêt. Maintien du conteneur en vie."
tail -f /dev/null
