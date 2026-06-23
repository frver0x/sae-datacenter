#!/usr/bin/env bash
# SAE4D01 DevCloud — Helper bootstrap containerlab
# Installe Docker + containerlab + images FRR/Alpine sur une VM Debian existante.
# Lance depuis n'importe quelle machine avec ansible et accès SSH à la VM cible.
set -euo pipefail

RD=$'\033[01;31m'; GN=$'\033[1;92m'; BL=$'\033[36m'; CL=$'\033[m'
msg_ok()   { echo -e " ${GN}✔${CL} $1"; }
msg_info() { echo -e " ${BL}➜${CL} $1"; }
die()      { echo -e " ${RD}✘ $1${CL}" >&2; exit 1; }

clear
cat <<'BANNER'
   ____      _      _____ _  _   ____   ___  _
  / ___|    / \    | ____| || | |  _ \ / _ \/ |
  \___ \   / _ \   |  _| | || |_| | | | | | | |
   ___) | / ___ \  | |___|__   _| |_| | |_| | |
  |____/ /_/   \_\ |_____|  |_| |____/ \___/|_|
        DevCloud — Bootstrap containerlab
BANNER
echo

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -d "$REPO/ansible" ] || die "Lance depuis la racine du repo."

command -v whiptail >/dev/null 2>&1 || sudo apt-get install -y -qq whiptail >/dev/null
command -v ansible  >/dev/null 2>&1 || sudo apt-get install -y -qq ansible  >/dev/null
msg_ok "Dépendances OK"

IP=$(whiptail --inputbox "IP de la VM cible" 10 60 "10.202.8.221" --title "SAE4D01 Helper" 3>&1 1>&2 2>&3)
KEY=$(whiptail --inputbox "Clé SSH privée" 10 60 "~/.ssh/id_ed25519" --title "SAE4D01 Helper" 3>&1 1>&2 2>&3)

whiptail --yesno "Bootstrap containerlab sur $IP ?" 8 60 --title "Confirmation" || die "Annulé."

cd "$REPO/ansible"
ansible-galaxy collection install -r requirements.yml -q

INV=$(mktemp --suffix=.yml)
cat > "$INV" <<EOF
all:
  children:
    containerlab_hosts:
      hosts:
        target:
          ansible_host: ${IP}
          ansible_user: root
          ansible_ssh_private_key_file: ${KEY}
EOF

msg_info "Bootstrap sur $IP..."
ansible-playbook -i "$INV" playbooks/bootstrap.yml
rm -f "$INV"
msg_ok "Terminé — containerlab installé sur $IP"
echo -e "   Deploy topo : ${BL}ansible-playbook playbooks/sync-topologies.yml${CL}"
