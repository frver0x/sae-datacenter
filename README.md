# SAE DevCloud — Fabric Datacenter EVPN/VXLAN

Notre société d'hébergement cloud **PIVAL** déploie deux nouveaux data-centers basés sur une architecture réseau "Leaf & Spine" hautement disponible. Ce projet s'appuie sur une démarche DevOps (Infrastructure as Code) et vise à fournir des services Web accessibles depuis le réseau 10.202.0.0/16.

Nous établissons également des partenariats d'interconnexion (peering BGP) avec nos data-centers pour échanger les différents VLANs entre plusieurs sites.

Le commanditaire est le Big Boss Pouchou.

# 🏗️ Architecture Réseau

## Premier Datacenter — Valentin (AS 65899)

Le premier datacenter (Valentin) repose sur un fabric leaf-spine déployé en 
Le routeur utilisé est un Arista cEOS 4.36.1.F

**iBGP, AS unique 65899**,
avec les spines configurés en route-reflectors pour l'underlay (AF IPv4) et l'overlay
(AF EVPN).

Le premier datacenter (Valentin) repose sur un fabric leaf-spine que j'ai monté avec
des routeurs Arista cEOS en version 4.36.1F.

J'ai fait le choix d'utiliser de l'**iBGP en AS unique (65899)** sur tout le fabric,
avec les deux spines configurés en route-reflectors, à la fois pour l'underlay
(AF IPv4) et l'overlay (AF EVPN).

- **2 spines** (spine1, spine2) : ils font office de route-reflectors. J'ai dû ajouter
  un peering iBGP direct entre eux (10.255.3.0/30), sinon ça ne fonctionnait pas :
  un RR ne réfléchit pas une route apprise d'un de ses clients vers les clients d'un
  autre RR, donc spine2 n'apprenait jamais les sous-réseaux locaux annoncés par
  spine1 (typiquement ceux du monitoring).
- **3 leafs** (leaf1, leaf2, leaf3) + **1 border-leaf** (bleaf), tous en cEOS 4.36.1F.
- **VXLAN** : VNI 560100 pour le VLAN 560 "web" et VNI 570100 pour le VLAN 570
  "machines", avec une gateway anycast en VARP (172.16.1.254 / 172.16.2.254) répartie
  sur les leafs concernés.
- **Supervision** : sFlow (avec la source forcée sur la loopback, sinon EOS refuse
  d'envoyer les datagrammes) → sFlow-RT → Prometheus → Grafana. Ces trois services
  sont rattachés directement à spine1 par des liens routés.
- **Sortie externe** : c'est bleaf qui s'en occupe, via son interface Ethernet3
  (10.202.8.205/16) reliée au réseau de la salle (10.202.0.0/16).
### Choix de conception : iBGP

J'ai choisi de partir sur de l'iBGP plutôt que de l'eBGP multi-AS (RFC 7938), qui est
pourtant le design le plus recommandé en datacenter moderne, et que Pierre a justement
implémenté sur son datacenter. Comme on devait couvrir les deux approches dans le
cadre de la SAE, j'ai pris l'iBGP pour qu'on ait les deux modèles représentés et qu'on
puisse comparer leurs contraintes respectives une fois les deux datacenters interconnectés.

Concrètement, ça m'a obligé à gérer des contraintes que l'eBGP n'a pas : il a fallu
mettre `next-hop-self` sur les spines pour l'underlay (sinon le next-hop des routes
apprises depuis les leafs n'est pas résoluble), déclarer explicitement
`route-reflector-client` sur chaque session, et ajouter un peering direct entre
spine1 et spine2 pour que les préfixes locaux d'un spine soient bien propagés vers
l'autre.

### Interconnexion EVPN inter-datacenter

Pour l'interconnexion avec le datacenter de Pierre, c'est bleaf (Border Leaf) qui sert de VTEP pour
les VNI 560100 et 570100, et qui établit le peering eBGP/EVPN avec son border-leaf.
Le VLAN 560 est étendu niveau L2  entre nos deux sites : on partage le même sous-réseau
(172.16.1.0/24), chacun avec une plage d'adresses réservée pour éviter qu'on se
marche dessus avec les mêmes IP.

### Schéma de l'infrastructure

![Schéma de l'infrastructure](../SAE-DevCloud/Images/Datacenter1.png)


## Deuxième Datacenter (Pierre)