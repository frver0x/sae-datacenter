# Grafana sur LXC — Notes déploiement (2026-06-22)

## Architecture finale

```
LAN salle (10.202.0.0/16)
        │
        ▼
pvepierre (10.202.8.101 / 10.202.8.102)
  ├── vmbr0 → campus (nic0)
  ├── vmbr31 → 192.168.80.1/24 → LXC1 (host-lxc1, VMID 213)
  └── vmbr32 → 192.168.81.1/24 → LXC2 (host-lxc2, VMID 214)

LXC1 (192.168.80.10) — Grafana + Prometheus stack
LXC2 (192.168.81.10) — LibreSpeed
```

## SNAT / DNAT sur pvepierre

| Accès LAN | Service | Destination interne |
|-----------|---------|-------------------|
| `10.202.8.101:3000` | Grafana | `192.168.80.10:3000` |
| `10.202.8.102:8888` | LibreSpeed | `192.168.81.10:8080` |

### Règles iptables (persistées via iptables-persistent)

```bash
# MASQUERADE sortie internet pour LXC
iptables -t nat -A POSTROUTING -s 192.168.80.0/24 -o vmbr0 -j MASQUERADE
iptables -t nat -A POSTROUTING -s 192.168.81.0/24 -o vmbr0 -j MASQUERADE
iptables -t nat -A POSTROUTING -s 192.168.82.0/24 -o vmbr0 -j MASQUERADE

# DNAT Grafana
iptables -t nat -A PREROUTING -i vmbr0 -p tcp --dport 3000 -j DNAT --to-destination 192.168.80.10:3000

# DNAT LibreSpeed (IP alias 10.202.8.102)
iptables -t nat -A PREROUTING -d 10.202.8.102 -i vmbr0 -p tcp --dport 8888 -j DNAT --to-destination 192.168.81.10:8080
```

### IP alias 10.202.8.102 (dans /etc/network/interfaces de pvepierre)

```
iface vmbr0 inet static
    ...
    up ip addr add 10.202.8.102/16 dev vmbr0 && arping -c3 -A -I vmbr0 10.202.8.102
```

### Gateway LXC (dans /etc/network/interfaces.d/leaf-spine de pvepierre)

vmbr31 et vmbr32 passés de `inet manual` à `inet static` avec adresses gateway :
- vmbr31 : `192.168.80.1/24`
- vmbr32 : `192.168.81.1/24`

## LXC1 — Grafana + Prometheus

### Stack Docker (network_mode: host pour tous les services)

Fichier : `/root/monitoring/docker-compose.yml`

Services actifs :
- `mon-prometheus` → port 9090
- `mon-grafana` → port 3000
- `mon-node` → port 9100
- `mon-pushgateway` → port 9091
- `mon-blackbox` → port 9115

**Pourquoi host network ?** Docker inside LXC (nesting=1) ne peut pas faire MASQUERADE iptables pour les ports publiés (`ports:`) → connexion refusée depuis l'extérieur. `network_mode: host` bind directement sur l'IP du LXC.

### prometheus.yml (/root/monitoring/prometheus.yml)

```yaml
global:
  scrape_interval: 5s
  evaluation_interval: 5s
  scrape_timeout: 4s

scrape_configs:
  - job_name: clab
    scrape_interval: 10s
    scrape_timeout: 9s
    static_configs:
      - targets: ['10.202.8.220:9101']   # clab_exporter VM220

  - job_name: node
    static_configs:
      - targets: ['10.202.8.220:9100']   # node-exporter VM220

  - job_name: pushgateway
    honor_labels: true
    static_configs:
      - targets: ['localhost:9091']

  - job_name: blackbox_icmp
    metrics_path: /probe
    params:
      module: [icmp]
    static_configs:
      - targets: [10.202.8.166, 10.202.8.253]
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: localhost:9115
```

**Pourquoi scrape_timeout 9s pour clab ?** clab_exporter = Python BaseHTTP single-thread HTTP/1.0, retourne ~28KB. Depuis Docker container le round-trip dépasse 2s → timeout par défaut. 9s fonctionne.

### Datasource Grafana (/root/monitoring/grafana/provisioning/datasources/ds.yml)

```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: true
```

**Pourquoi localhost ?** En host network, plus de DNS Docker → `http://prometheus:9090` ne résout pas.

### Dashboard provisionné

Fichier : `/root/monitoring/grafana/dashboards/sae4d01.json`
Source : exporté depuis VM220 `http://10.202.8.220:3000/api/dashboards/uid/sae4d01`
UID : `sae4d01`, titre : `SAE4D01 — VM220 Prod eBGP + bleaf FRR`

Accès : `http://10.202.8.101:3000/d/sae4d01`

**Dashboard provisionné depuis fichier** (pas importé via API) → persiste aux restarts du container.

## LXC2 — LibreSpeed

```bash
docker run -d --restart unless-stopped --name librespeed --network=host \
  -e MODE=standalone -e TITLE='SAE4D01 SpeedTest' \
  -e TELEMETRY=false -e USE_NEW_DESIGN=true -e WEBPORT=8080 \
  ghcr.io/librespeed/speedtest:latest
```

`network_mode: host` pour la même raison que LXC1.

Accès : `http://10.202.8.102:8888`

## Route par défaut persistante sur les LXC

Ajouté dans `/etc/network/interfaces` de chaque LXC :

**LXC1 (213) :**
```
auto eth1
iface eth1 inet static
    address 192.168.80.10/24
    gateway 192.168.80.1
```

**LXC2 (214) :**
```
auto eth1
iface eth1 inet static
    address 192.168.81.10/24
    gateway 192.168.81.1
```

## Bugs / gotchas rencontrés

| Problème | Cause | Fix |
|----------|-------|-----|
| Docker container ne peut pas publier ports dans LXC | iptables MASQUERADE inopérant dans LXC nesting | `network_mode: host` sur tous les services |
| Datasource Grafana "no data" | URL `http://prometheus:9090` → DNS Docker mort en host network | `http://localhost:9090` |
| clab scrape timeout | clab_exporter HTTP/1.0 single-thread lent, scrape_timeout=2s trop court | `scrape_interval: 10s`, `scrape_timeout: 9s` sur le job clab |
| Dashboard perdu au restart | Importé via API → DB SQLite container non persistée | Sauvegarde JSON dans `/grafana/dashboards/sae4d01.json` (provisioning fichier) |
| 10.202.8.102 injoignable depuis LAN | IP alias pas annoncée ARP | `arping -A -I vmbr0 10.202.8.102` au boot |
