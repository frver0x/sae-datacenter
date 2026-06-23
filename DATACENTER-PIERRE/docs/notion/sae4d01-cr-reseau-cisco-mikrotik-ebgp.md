# SAE4D01 — CR Réseau : Cisco + Mikrotik + eBGP (Groupe 8)

> Source : page Notion (groupe 8, SAE4D01). 2026-06-17.
> Routeur perso **Cisco C8000V-G8 (AS65080)** + **Mikrotik (AS65081)** en leaf, sur le L2 partagé campus `10.202.0.0/16`. eBGP réel entre groupes.

## 1. Objectif

- Rendre le **Mikrotik joignable depuis l'extérieur** (autres groupes).
- Renuméroter le lien Cisco↔Mikrotik.
- Diagnostiquer pourquoi un collègue ne ping pas le Mikrotik.

## 2. Infrastructure physique

| Élément | IP | Rôle |
| --- | --- | --- |
| Cisco Gi1 | `10.202.8.253/16` | uplink campus (L2 partagé) |
| Cisco Gi2 | `172.80.0.2/30` | lien dédié vers Mikrotik |
| Cisco Lo0 | `172.80.255.1/32` | IP stable hors zone partagée |
| Mikrotik | `172.80.0.1/30` | leaf, AS65081 |
| Derrière Mikrotik | `172.17.0.0/24` | services |

```
[172.17.0.0/24] -- Mikrotik(172.80.0.1, AS65081)
                      |  lien dédié /30
                   Cisco Gi2(172.80.0.2, AS65080)
                   Cisco Gi1(10.202.8.253)
                      |
        === L2 PARTAGÉ campus 10.202.0.0/16 ===
          |              |             |
   collègue AS65001   AS65060      (autres groupes)
   10.202.1.12       10.202.60.22
```

## 3. Accès SSH au Cisco

Crypto legacy → options à forcer (ou plain `ssh admin@10.202.8.253` marche aussi) :

```
ssh -o KexAlgorithms=+diffie-hellman-group14-sha1 \
    -o HostKeyAlgorithms=+ssh-rsa \
    -o PubkeyAcceptedAlgorithms=+ssh-rsa admin@10.202.8.253
```

## 4. Renumérotation du lien 172.20.0.0/30 → 172.80.0.0/30

Côté Cisco (Gi2 = `.2`), côté Mikrotik (`.1`). Session BGP AS65080↔AS65081 ré-établie, `172.17.0.0/24` réappris via `172.80.0.1`.

## 5. Annonce BGP

```
router bgp 65080
 network 172.80.0.0 mask 255.255.255.252
 network 172.80.255.1 mask 255.255.255.255
```

Vérif annonce poussée aux peers :

```
C8000V-G8#show bgp ipv4 unicast neighbors 10.202.1.12 advertised-routes | include 172.80
 *>   172.17.0.0/24    172.80.0.1                             0 65081 i
 *>   172.80.0.0/30    0.0.0.0                  0         32768 i
 *>   172.80.255.1/32  0.0.0.0                  0         32768 i
```

## 6. Loopback (IP stable hors zone partagée)

```
interface Loopback0
 ip address 172.80.255.1 255.255.255.255
```

**Pourquoi** : hors `10.202.0.0/16` → pas shadowée par le /16 connecté de tous les groupes → joignable de partout (longest-match /32 bat /16).

## 7. Chemin retour Mikrotik

```
/ip route add dst-address=0.0.0.0/0 gateway=172.80.0.2
```

Vérif depuis le Cisco — ping Mikrotik avec sources différentes :

```
C8000V-G8#ping 172.80.0.1
!!!!!  Success rate is 100 percent (5/5)
C8000V-G8#ping 172.80.0.1 source Loopback0
Packet sent with a source address of 172.80.255.1
!!!!!  Success rate is 100 percent (5/5)
C8000V-G8#ping 172.80.0.1 source GigabitEthernet1
Packet sent with a source address of 10.202.8.253
!!!!!  Success rate is 100 percent (5/5)
```

✅ Le test `source Loopback0` (IP non-connectée) force le Mikrotik à utiliser sa default route → 100% prouve : forward OK, return OK, pas de firewall drop.

## 8. Diagnostic : collègue ne ping pas le Mikrotik

Côté collègue (Cisco AS65001, `10.202.1.12`) — routes parfaites :

```
Router#show ip route 172.80.255.1
Known via "bgp 65001", distance 20, type external
  via 10.202.8.253, AS Hops 1, Route tag 65080
```

Mais ping = 0% :

```
Router#ping 172.80.0.1 source GigabitEthernet2
Packet sent with a source address of 10.202.1.12
.....  Success rate is 0 percent (0/5)
```

Et log BGP qui flappe pendant le test :

```
%BGP-3-NOTIFICATION: received from neighbor 10.202.8.253 4/0 (hold time expired)
%BGP-5-ADJCHANGE: neighbor 10.202.8.253 Down ... Up
```

## 9. Root cause : le L2 partagé perd des paquets

`show ip bgp neighbors` — compteurs de connexions :

```
10.202.1.12 (collègue) : Connections established 2076; dropped 2075   up 00:02:12
10.202.60.22 (AS65060) : Connections established 920;  dropped 919    up 00:02:15
172.80.0.1  (Mikrotik) : Connections established 1;    dropped 0      up 01:37:35
TCP collègue : retransmit 5, SRTT 413ms, RTTO 3205ms, maxRTT 1000ms
```

`show ip bgp summary` :

```
Neighbor      V      AS  MsgRcvd MsgSent  Up/Down  State/PfxRcd
10.202.0.227  4   65014       0       0  1d23h     Idle
10.202.1.12   4   65001      12       5  00:00:18    12   <- FLAP
10.202.7.253  4   65070       0       0  02:22:00  Idle
10.202.8.249  4   65082       0       0  never     Idle
10.202.60.22  4   65060       9       5  00:00:18    12   <- FLAP
172.80.0.1    4   65081     108     341  01:44:50     1   <- STABLE
```

> ⚠️ **Conclusion** : les voisins du **L2 partagé** (`10.202.x`) flappent (uptime ~18s, 2000+ drops). Le Mikrotik sur **lien dédié** Gi2 tient 1h44, 0 drop. → Le segment partagé `10.202.0.0/16` perd des paquets en masse. Le ping du collègue ET son BGP tombent dedans. **Pas un défaut de routage** — routage prouvé bon des 2 côtés.

### Pourquoi moi je ping le Mikrotik et pas le collègue

```
Moi      : Cisco -> Gi2 (lien dédié) -> Mikrotik           => jamais le LAN pourri => 100%
Collègue : Cisco -> L2 PARTAGÉ (drop) -> mon Cisco -> Gi2  => meurt sur le LAN => 0%
```

## 10. Bilan infra perso

- ✅ Lien dédié /30 Cisco↔Mikrotik stable (0 drop, 1h44).
- ✅ eBGP AS65080↔AS65081 propre, préfixes échangés.
- ✅ Renumérotation `172.80.0.0/30` sans casse.
- ✅ Loopback hors zone partagée + annoncée (bonne pratique).
- ✅ Default route Mikrotik (retour propre).
- ✅ Annonces poussées aux 2 peers UP.
- ❌ (hors contrôle) L2 partagé mutualisé qui drop → flap BGP.

## 11. Ce qui manque / à compléter

- [ ] **Screenshots réels** (winbox Mikrotik, dashboard webui Cisco `https://10.202.8.253/webui`).
- [ ] **Config complète Mikrotik** (`/export`).
- [ ] **Running-config Cisco** (`show run`) annexé en preuve.
- [ ] **Mesure du taux de perte exact** du LAN partagé (ping étendu 100 paquets / capture).
- [ ] **Conclusion/recommandation** : isoler le trafic inter-groupes du broadcast domain partagé (VLAN par groupe / sous-réseau dédié) pour éviter le flap.

## 12. Pages source des preuves

- [pierre-ha-ebgp-physique.md](pierre-ha-ebgp-physique.md) — topo LAN, 2 VMs Debian
- [pierre-containerlab-leaf-spine-15-06-2026.md](pierre-containerlab-leaf-spine-15-06-2026.md) — captures fabric leaf-spine
- [pierre-bgplab-evpn-vxlan-lab1.md](pierre-bgplab-evpn-vxlan-lab1.md) — captures VXLAN/EVPN
- [pierre-c8000v-setup.md](pierre-c8000v-setup.md) — déploiement C8000v
