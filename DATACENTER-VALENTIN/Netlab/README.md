## Architecture BGP en Datacenter : iBGP vs eBGP

Ce projet met en place une topologie réseau de type Spine-Leaf conteneurisée. L'objectif principal est de comparer deux approches de routage dynamique en datacenter.

J'ai fait le choix d'implémenter un modèle iBGP en AS unique avec Route-Reflectors, tandis que mon binôme Pierre a déployé le modèle de référence moderne eBGP multi-AS (RFC 7938 : un AS par équipement, réécriture automatique du next-hop, ECMP naturel via l'AS-path).

## 🏗️ Choix de conception : l'approche iBGP

Le choix de l'iBGP a été fait délibérément pour explorer une approche alternative et en mesurer les contraintes de configuration réelles. Contrairement à l'eBGP, ce modèle nécessite des ajustements spécifiques :


- `next-hop-self` obligatoire sur les spines car sans cela, les routes de l'underlay sont reçues mais ne sont pas installées, car le next-hop reste irrésoluble.

- Sessions Route-Reflector (RR) : Il est nécessaire de déclarer manuellement les sessions route-reflector-client côté spines.

- Peering direct entre Spines (spine1 ↔ spine2) : Indispensable dans ce design. Un RR ne réfléchissant pas les routes entre les clients d'un autre RR, cette session directe permet à spine2 d'apprendre les préfixes locaux de spine1 (comme les sous-réseaux de monitoring).

## Prérequis

- netlab + containerlab installés
- Images dans le registre local :
  - `ceos:4.36.1F`
  - `prometheus-sae:latest` et `sflowrt-sae:latest` (images custom, voir ci-dessous)

### Construction des images custom

```bash
# sflowrt avec apps browse-flows / browse-metrics précâblées
docker build -t sflowrt-sae:latest -f Docker/sflowrt/Dockerfile .

# prometheus avec prometheus.yml (scrape de sflow-rt) précâblé
docker build -t prometheus-sae:latest -f Docker/prometheus/Dockerfile .
```

## Déploiement


Toute la configuration des équipements est embarquée dans `topology.yml` via le plugin
`files` (`config.inline` par nœud).

```bash
for i in {101..150}; do
  ssh-keygen -R "192.168.121.$i"
done

netlab status -i default --cleanup
netlab up
```

## Accès aux services

| Service | URL |
| --- | --- |
| Grafana | http://<hôte>:3000 |
| Prometheus | http://<hôte>:9090 |
| sFlow-RT | http://<hôte>:8008 |
| nginx1 / nginx2 | http://<hôte>:80 / :81 |
| LibreSpeed | http://<hôte>:8080 |
| Bureau distant (webtop) | rdp://<hôte>:3389 |

# Tableaux d'adressage

| **Équipement** | **Rôle** | **Interface** | **Adresse IP** | **Masque** |
| --- | --- | --- | --- | --- |
| **spine1** | Spine | Loopback0 | 10.255.0.1 | /32 |
| **spine2** | Spine | Loopback0 | 10.255.0.2 | /32 |
| **leaf1** | Leaf | Loopback0 | 10.0.0.1 | /32 |
| **leaf2** | Leaf | Loopback0 | 10.0.0.2 | /32 |
| **leaf3** | Leaf | Loopback0 | 10.0.0.3 | /32 |
| **bleaf** | Border Leaf | Loopback0 | 10.0.0.4 | /32 |

### Liens Point-à-Point (Underlay IP Fabric)

| **Nœud A** | **IP Nœud A** | **Nœud B** | **IP Nœud B** | **Réseau / Masque** |
| --- | --- | --- | --- | --- |
| **spine1** | 10.255.1.1 | **leaf1** | 10.255.1.2 | 10.255.1.0/30 |
| **spine1** | 10.255.1.5 | **leaf2** | 10.255.1.6 | 10.255.1.4/30 |
| **spine1** | 10.255.1.9 | **leaf3** | 10.255.1.10 | 10.255.1.8/30 |
| **spine1** | 10.255.1.13 | **bleaf** | 10.255.1.14 | 10.255.1.12/30 |
| **spine2** | 10.255.2.1 | **leaf1** | 10.255.2.2 | 10.255.2.0/30 |
| **spine2** | 10.255.2.5 | **leaf2** | 10.255.2.6 | 10.255.2.4/30 |
| **spine2** | 10.255.2.9 | **leaf3** | 10.255.2.10 | 10.255.2.8/30 |
| **spine2** | 10.255.2.13 | **bleaf** | 10.255.2.14 | 10.255.2.12/30 |
| **spine1** | 10.255.3.1 | **spine2** | 10.255.3.2 | 10.255.3.0/30 |

### Serveurs et Équipements Terminaux (Overlay - VLAN 560 "web")

| **Serveur / Conteneur** | **Adresse IP** | **Masque** | **Connecté à (Switch)** |
| --- | --- | --- | --- |
| **nginx1** | 172.16.1.1 | /24 | leaf1 |
| **nginx2** | 172.16.1.2 | /24 | leaf1 |
| **librespeed** | 172.16.1.3 | /24 | leaf2 |
| **remotedesktop** | 172.16.1.4 | /24 | leaf2 |

> Gateway anycast (VARP) : **172.16.1.254** — MAC virtuelle `00:1c:73:00:00:99`

### Réseau de Supervision

| **Service** | **IP Service** | **Nœud Spine** | **IP Spine** | **Réseau / Masque** |
| --- | --- | --- | --- | --- |
| **sflowrt** | 10.255.9.2 | **spine1** | 10.255.9.1 | 10.255.9.0/30 |
| **grafana** | 10.255.10.2 | **spine1** | 10.255.10.1 | 10.255.10.0/30 |
| **prometheus** | 10.255.11.2 | **spine1** | 10.255.11.1 | 10.255.11.0/30 |

### Border Leaf et connectivité externe

| **Nœud** | **Interface / Rôle** | **Adresse IP** | **Masque** | **Passerelle / Peer BGP** |
| --- | --- | --- | --- | --- |
| **bleaf** | Uplink (ens18) / Externe | 10.202.8.205 | /16 | Route par défaut via 10.202.255.254 |
| **bleaf** | Peering eBGP (Pierre-EVPN) | - | - | 10.202.8.12 (AS 65084) |

## Supervision sFlow

Chaque équipement exporte son sFlow vers sFlow-RT (10.255.9.2:6343), source forcée sur
la loopback (`sflow source-interface Loopback0`, sans quoi aucun datagramme n'est émis).
sFlow-RT expose ses métriques au format Prometheus
(`/prometheus/metrics/ALL/ALL/txt`), scrapées par Prometheus puis visualisées dans
Grafana.

## Limitations connues / pistes d'amélioration

- **NAT sortant du VLAN 560** : non fonctionnel. `ip nat source dynamic` est supporté
  sous cEOS 4.33.1F mais retourne `% Unrecognized command` sous 4.36.1F (y compris en
  SVI) — la fonctionnalité NAT native n'est pas disponible sur cette version
  conteneurisée. Piste de repli : NAT côté hôte (iptables) ou conteneur NAT dédié
  (Alpine), non finalisé.
- **Exposition externe des conteneurs** : les SYN atteignent l'hôte (ens18) et le
  binding Docker est correct (0.0.0.0), mais aucun SYN-ACK ne repart — blocage dans la
  chaîne FORWARD/NAT de Docker à investiguer.
- **Interconnexion Pierre** : configurée côté bleaf (extension L2 du VLAN 560, sous-réseau
  172.16.1.0/24 partagé avec plages d'IP réparties), en attente de la configuration côté
  Cisco. AS à confirmer (65080 vs 65084).
