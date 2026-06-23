# SAE4D01 DevCloud — Planning & Document d'Architecture Technique (DAT)

**Projet :** Fabric Datacenter EVPN/VXLAN — Société d'hébergement cloud **PIVAL**
**Binôme :** Pierre (datacenter eBGP multi-AS) · Valentin MALOT (datacenter iBGP AS unique)
**Interconnexions partenaires :** Pierre (AS 65080) · Soyfoudine (AS 65001)
**Commanditaire :** Jean-Marc Pouchoulon (« Big Boss Pouchou »)
**Salle :** B202 · **Période :** 8 juin → 8 juillet 2026
**Document mis à jour le :** 22 juin 2026

---

## 1. Légende des séances

| Code | Signification | Usage dans ce projet |
| --- | --- | --- |
| **CM** | Cours Magistral | Apports théoriques (BGP, EVPN, VXLAN, IaC) |
| **TD** | Travaux Dirigés | Conception guidée, design d'adressage, revue |
| **TP** | Travaux Pratiques | Déploiement / config sur le lab |
| **E** | Encadré | Travail projet en présence de l'enseignant |
| **NE** | Non Encadré | Travail projet en autonomie |
| **Portfolio** | Suivi portfolio | Rédaction docs, synthèse, captures, soutenance |

---

## 2. Planning détaillé (calendrier réel)

> Horaires en UTC, salle B202. Le planning ci-dessous mappe les tâches du projet
> sur les créneaux réels de l'emploi du temps.

### Semaine 1 — Cadrage & socle du fabric

| Date | Créneau | Type | Tâche projet |
| --- | --- | --- | --- |
| **Lun 8 juin** | 06:00–10:15 | CM ×3 | Théorie : underlay IP fabric, iBGP vs eBGP (RFC 7938), MP-BGP/EVPN, VXLAN, sFlow |
| | 12:00–16:15 | TD ×3 | Conception : choix de design (Pierre→eBGP, Valentin→iBGP), plan d'adressage, schéma topo leaf-spine |
| **Mar 9 juin** | 06:00–16:15 | NE ×7 | Mise en place outillage : netlab + containerlab, import images `ceos:4.36.1F`, premier `netlab up`, vérif liens |
| **Mer 10 juin** | 06:00–10:15 | TD ×3 | Underlay : adressage P2P /30, sessions BGP underlay, loopbacks, vérif `show ip bgp summary` |
| | 12:00–14:45 | TP | Overlay EVPN : address-family evpn, RR sur spines (côté Valentin), redistribution |
| | 15:00–16:15 | Portfolio (E) | Démarrage portfolio, captures d'écran underlay |
| **Jeu 11 juin** | 06:00–10:15 | E ×3 | VXLAN : VNI 560100 (VLAN 560 web) / 570100 (VLAN 570 machines), interface Vxlan1, RD/RT |
| **Ven 12 juin** | 06:00–13:15 | E ×4 | Gateway anycast VARP (172.16.1.254 / 172.16.2.254), MAC virtuelle partagée, test inter-leaf |
| | 13:30–16:15 | Portfolio (NE) | Documentation tableaux d'adressage, rédaction README |

### Semaine 2 — Services, monitoring & robustesse

| Date | Créneau | Type | Tâche projet |
| --- | --- | --- | --- |
| **Lun 15 juin** | 06:00–07:15 | TD | Revue topologie, intégration des hosts conteneurisés |
| | 07:30–10:15 | TP | Déploiement services : nginx1/2, librespeed, webtop (remotedesktop), networkutils + routes statiques (`routing.static`, conteneurs sans root) |
| | 12:00–13:15 | TD | Conception réseau de supervision (liens routés P2P plutôt que VLAN) |
| | 13:30–16:15 | TP | Monitoring : sflowrt, prometheus, grafana reliés à spine1 (10.255.9-11.0/30), `network` d'annonce |
| **Mar 16 juin** | 06:00–08:45 | NE ×2 | Images Docker custom (`prometheus-sae`, `sflowrt-sae` avec browse-flows/metrics précâblés) |
| | 09:00–10:15 | Portfolio (E) | Suivi portfolio |
| | 12:00–16:15 | E ×3 | Config sFlow par équipement (`sflow source-interface Loopback0` obligatoire), chaîne sFlow-RT → Prometheus → Grafana |
| **Mer 17 juin** | 06:00–07:15 | TD | Résolution incident RR : peering iBGP direct spine1↔spine2 (10.255.3.0/30) — préfixes monitoring non propagés |
| | 07:30–10:15 | TP | Test ECMP (`maximum-paths 2 ecmp 2`), validation overlay bout-en-bout |
| | 12:00–13:15 | TD | Revue : `next-hop-self` sur spines (underlay iBGP), `route-reflector-client` explicite |
| | 13:30–16:15 | TP | Dashboards Grafana, vérification scraping Prometheus |
| **Jeu 18 juin** | 06:00–10:15 | NE ×3 | Tentative NAT sortant VLAN 560 (échec : `% Unrecognized command` sous cEOS 4.36.1F) |
| **Ven 19 juin** | 06:00–16:15 | NE ×9 | Investigation exposition externe conteneurs (SYN reçus sur ens18, pas de SYN-ACK) ; piste NAT hôte/Alpine |

### Semaine 3 — Interconnexion inter-datacenter & finalisation

| Date | Créneau | Type | Tâche projet |
| --- | --- | --- | --- |
| **Lun 22 juin** | 06:00–07:15 | E | Border-leaf : config uplink salle (ens18, 10.202.8.205/16), route par défaut 10.202.255.254 |
| | 07:30–08:45 | CM | Apport peering inter-AS / interconnexion EVPN |
| | 09:00–10:15 | TD | Conception interco : eBGP/EVPN bleaf ↔ Pierre (AS 65080) et ↔ Soyfoudine (AS 65001) |
| | 12:00–14:45 | TP | Config peering EVPN sur bleaf : route-targets multi-AS (65080:560, 65001:560…), `ebgp-multihop 3` |
| **Mar 23 juin** | 06:00–14:45 | E ×5 | Tests interco : extension L2 VLAN 560 (sous-réseau 172.16.1.0/24 partagé, plages d'IP réparties), validation MAC/ARP cross-site |
| **Mer 24 juin** | 06:00–10:15 | NE ×3 | Reprise des points bloquants (NAT, exposition externe), nettoyage configs |
| | 12:00–14:45 | Portfolio (TP) | Finalisation portfolio, captures interco |
| **Jeu 25 juin** | 06:00–10:15 | NE ×3 | Rédaction synthèse, relecture README/DAT, préparation soutenance |

### Échéances finales

| Date | Créneau | Type | Tâche projet |
| --- | --- | --- | --- |
| **Lun 6 juil** | 06:00–16:15 | Soutenances COMPÉTENCES | Présentation portfolios (jury R&T 2e année BUT) |
| **Mar 7 juil** | 06:00–16:15 | Soutenance SAE / Stage | Soutenance finale SAE DevCloud |

---

## 3. Document d'Architecture Technique (DAT)

### 3.1 Contexte & objectifs

La société **PIVAL** déploie deux datacenters basés sur une architecture **Leaf & Spine**
hautement disponible, dans une démarche **DevOps / Infrastructure as Code**. Objectif :
fournir des services Web accessibles depuis le réseau **10.202.0.0/16**, et établir des
**peerings BGP/EVPN** entre sites pour échanger les VLANs.

Deux modèles de plan de contrôle sont volontairement comparés :

| Datacenter | Responsable | Modèle BGP | Justification |
| --- | --- | --- | --- |
| DC1 | **Valentin** | **iBGP AS unique 65899** + Route-Reflectors | Explorer les contraintes du design legacy |
| DC2 | **Pierre** | **eBGP multi-AS** (RFC 7938) | Design de référence datacenter moderne |

### 3.2 Topologie physique (DC1 — Valentin)

```
                 ┌─────────┐        ┌─────────┐
                 │ spine1  │◄──────►│ spine2  │   (RR + peering direct 10.255.3.0/30)
                 └────┬────┘        └────┬────┘
       ┌──────┬───────┼─────────┬────────┼───────┬──────┐
   ┌───▼──┐┌──▼───┐┌──▼───┐ ┌───▼──┐ (chaque leaf ↔ chaque spine)
   │leaf1 ││leaf2 ││leaf3 │ │bleaf │──► salle 10.202.0.0/16 (ens18)
   └──┬───┘└──┬───┘└──┬───┘ └──────┘──► eBGP/EVPN ↔ Pierre (AS 65080)
  nginx1/2  libre-  network-          └► eBGP/EVPN ↔ Soyfoudine (AS 65001)
            speed   utils
            webtop  (VLAN570)
  (VLAN560 web)
```

- **2 spines** (spine1, spine2) : route-reflectors underlay (AF IPv4) + overlay (AF EVPN).
- **3 leafs** (leaf1, leaf2, leaf3) + **1 border-leaf** (bleaf), tous en cEOS **4.36.1F**.
- **Monitoring** (grafana, prometheus, sflowrt) rattaché en liens routés P2P à spine1.

### 3.3 Plan d'adressage

**Loopbacks (Router-ID / VTEP)**

| Équipement | Rôle | Loopback0 |
| --- | --- | --- |
| spine1 | Spine / RR | 10.255.0.1/32 |
| spine2 | Spine / RR | 10.255.0.2/32 |
| leaf1 | Leaf | 10.0.0.1/32 |
| leaf2 | Leaf | 10.0.0.2/32 |
| leaf3 | Leaf | 10.0.0.3/32 |
| bleaf | Border Leaf | 10.0.0.4/32 |

**Underlay (liens P2P /30)** — bloc `10.255.1.0/24` (vers spine1), `10.255.2.0/24` (vers spine2), peering spines `10.255.3.0/30`.

**Overlay**

| VLAN | VNI | Sous-réseau | Gateway anycast (VARP) |
| --- | --- | --- | --- |
| 560 « web » | 560100 | 172.16.1.0/24 | 172.16.1.254 |
| 570 « machines » | 570100 | 172.16.2.0/24 | 172.16.2.254 |

> MAC virtuelle VARP partagée : `00:1c:73:00:00:99`

**Supervision** — `10.255.9.0/30` (sflowrt), `10.255.10.0/30` (grafana), `10.255.11.0/30` (prometheus), tous vers spine1.

**Connectivité externe** — bleaf uplink `10.202.8.205/16` (ens18), défaut via `10.202.255.254`.

### 3.4 Plan de contrôle — iBGP + EVPN

- **AS unique 65899** sur tout le fabric.
- Spines = **route-reflectors** : `route-reflector-client` déclaré explicitement sur chaque session.
- **`next-hop-self`** obligatoire sur les spines (underlay AF IPv4), sinon next-hop irrésoluble → routes reçues mais non installées.
- **Peering direct spine1↔spine2** (10.255.3.0/30) : sans lien entre RR, spine2 n'apprend pas les préfixes locaux annoncés par spine1 (sous-réseaux de monitoring) — un RR ne réfléchit pas les routes entre clients d'un autre RR.
- Overlay : `address-family evpn`, `send-community extended`, RD par leaf (`10.0.0.x:560`), route-target `both 65899:560`.
- **ECMP** : `maximum-paths 2 ecmp 2`.

### 3.5 Plan de données — VXLAN

- Interface `Vxlan1`, `vxlan source-interface Loopback0`, `udp-port 4789`.
- Mapping VLAN→VNI : 560→560100, 570→570100.
- VTEP sur chaque leaf + bleaf.

### 3.6 Supervision (sFlow → Prometheus → Grafana)

```
[chaque équipement] --sFlow(6343)--> [sFlow-RT 10.255.9.2]
       │ sflow source-interface Loopback0 (obligatoire, sinon aucun datagramme)
       ▼
[sFlow-RT] --/prometheus/metrics/ALL/ALL/txt--> [Prometheus] --> [Grafana]
```

- Images Docker custom : `prometheus-sae` (prometheus.yml précâblé), `sflowrt-sae` (apps browse-flows / browse-metrics).
- Hosts conteneurisés : routes par défaut via `routing.static` / `nexthop` (pas de root dans les conteneurs).

### 3.7 Interconnexion inter-datacenter (border-leaf)

- bleaf = VTEP pour VNI 560100 / 570100 + peerings **eBGP/EVPN** :
  - ↔ **Pierre** : `neighbor 10.202.8.253 remote-as 65080`, `ebgp-multihop 3`
  - ↔ **Soyfoudine** : `neighbor 10.202.1.12 remote-as 65001`, `ebgp-multihop 3`
- Route-targets multi-AS sur les VLANs (ex. `route-target both 65080:560`, `65001:560`).
- **Extension L2 du VLAN 560** : sous-réseau `172.16.1.0/24` partagé entre sites, plages d'IP réparties pour éviter les collisions.

### 3.8 Services exposés

| Service | URL | Hôte / Leaf |
| --- | --- | --- |
| Grafana | `http://<hôte>:3000` | spine1 (P2P) |
| Prometheus | `http://<hôte>:9090` | spine1 (P2P) |
| sFlow-RT | `http://<hôte>:8008` | spine1 (P2P) |
| nginx1 / nginx2 | `:80` / `:81` | leaf1 (VLAN 560) |
| LibreSpeed | `:8080` | leaf2 (VLAN 560) |
| Bureau distant (webtop) | `rdp://<hôte>:3389` | leaf2 (VLAN 560) |

### 3.9 Risques, limitations & dette technique

| Sujet | État | Détail / piste |
| --- | --- | --- |
| **NAT sortant VLAN 560** | ❌ Échec | `ip nat source dynamic` OK sous cEOS 4.33.1F, `% Unrecognized command` sous 4.36.1F (y compris SVI). NAT natif indisponible sur cette image conteneurisée. Piste : NAT hôte (iptables) ou conteneur Alpine dédié (non finalisé). |
| **Exposition externe des conteneurs** | ❌ Échec | SYN atteignent l'hôte (ens18), binding Docker correct (0.0.0.0), mais aucun SYN-ACK ne repart. Blocage chaîne FORWARD/NAT Docker à investiguer. |
| **Interconnexion Pierre** | ⚠️ En cours | Configurée côté bleaf, en attente config côté Cisco. AS à confirmer (65080 vs 65084). |
| **Configs manuelles iBGP** | ⚠️ Dette | RR + `next-hop-self` + peering inter-spine = maintenance lourde en prod vs eBGP. |

### 3.10 Procédure de déploiement (IaC)

```bash
# 1. Construire les images custom
docker build -t sflowrt-sae:latest    -f Docker/sflowrt/Dockerfile.sflowrt .
docker build -t prometheus-sae:latest -f Docker/Prometheus/Dockerfile.prometheus .

# 2. Purger les clés SSH des anciens nœuds
for i in {101..150}; do ssh-keygen -R "192.168.121.$i"; done

# 3. Déployer (toute la conf est embarquée dans topology.yml via plugin files)
netlab status -i default --cleanup
netlab up
```

---

## 4. Synthèse des compétences mobilisées (portfolio)

- **Conception réseau datacenter** : architecture Leaf & Spine, choix iBGP vs eBGP argumenté.
- **Routage avancé** : BGP, Route-Reflectors, MP-BGP/EVPN, route-targets, ECMP.
- **Virtualisation réseau** : VXLAN (VTEP, VNI), gateway anycast VARP.
- **Infrastructure as Code** : netlab + containerlab, conf inline `topology.yml`, images Docker custom.
- **Supervision / observabilité** : sFlow, sFlow-RT, Prometheus, Grafana.
- **Interconnexion inter-site** : peering eBGP/EVPN multi-AS, extension L2 inter-datacenter.
- **Démarche de résolution d'incidents** : diagnostic RR/split-horizon, NAT cEOS, exposition Docker.
