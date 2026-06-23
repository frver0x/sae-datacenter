# État lab — topo-ebgp + bleaf + LXC

## Architecture actuelle

```
                Internet
                    |
           bleaf (AS65080)
           eth3=10.202.8.253/16  ← br-campus → ens23 → campus/salle
           eth1=10.0.1.13/31     ← spine1 eth4
           eth2=10.0.1.15/31     ← spine2 eth4
           lo=10.255.0.20/32
           SNAT: 192.168.80.0/22 → eth3
                /       \
          spine1          spine2
         (AS65081)       (AS65082)
          /  |  \         /  |  \
       leaf1 leaf2 leaf3
      (65083)(65084)(65085)
        |      |      |
   br-lxc1 br-lxc2 br-lxc3
     (ens19) (ens20) (ens21)
       |       |       |
    vmbr31  vmbr32  vmbr33   ← Proxmox
       |       |       |
    LXC213  LXC214  LXC215
  .80.10/24 .81.10/24 .82.10/24
```

## LXC containers

| LXC | VMID | IP | GW | NIC unique |
|-----|------|----|----|-----------|
| host-lxc1 | 213 | 192.168.80.10/24 | 192.168.80.1 (leaf1 eth3) | eth1 → vmbr31 |
| host-lxc2 | 214 | 192.168.81.10/24 | 192.168.81.1 (leaf2 eth3) | eth1 → vmbr32 |
| host-lxc3 | 215 | 192.168.82.10/24 | 192.168.82.1 (leaf3 eth3) | eth1 → vmbr33 |

- eth0 (campus vmbr0) **supprimé** de tous les LXC — 100% routage par le lab
- IPs en `.10` (pas `.213/.214/.215`) pour éviter conflit avec routes BGP campus plus-spécifiques (192.168.80.128/25, etc.)

## Ce qui fonctionne

- BGP eBGP fabric : spine1/spine2 ↔ leaf1/leaf2/leaf3 ↔ bleaf — tous Established
- `default-originate` de bleaf → spines → leafs : route default BGP propagée dans tout le fabric
- SNAT MASQUERADE sur bleaf (192.168.80.0/22 → eth3) : LXC → internet OK (8.8.8.8 ~15ms)
- LXC213 ↔ leaf1, LXC214 ↔ leaf2, LXC215 ↔ leaf3 : ping GW OK, ping internet OK
- **EVPN inter-DC VNI 560100/570100 ↔ Valentin (AS65899) : 0% loss dans les deux sens** ✅

## Problèmes résolus dans cette session

### 1. bleaf eth1/eth2/eth3 manquants (veth orphelins)
Après un destroy partiel, les veth `lxc1/lxc2/lxc3/campus1` restaient attachés aux bridges.
Le redeploy échouait avec "Interface already exists".
Fix :
```bash
ip link delete lxc1; ip link delete lxc2; ip link delete lxc3; ip link delete campus1
cd /root/topo-ebgp && containerlab deploy -t topology.clab.yml --reconfigure
```

### 2. Exec clab sans shell — `2>/dev/null || true` rejeté
Containerlab exec passe les commandes directement à docker exec (pas de shell).
`ip route del default via 172.20.20.1 dev eth0 2>/dev/null || true` → ip interprète `2>/dev/null` comme argument → ERRO.
Fix : wrapper `/bin/sh -c '...'` dans topology.clab.yml.

### 3. Route mgmt clab (172.20.20.1) écrase la default BGP
Containerlab injecte `default via 172.20.20.1 dev eth0` (distance 0) sur tous les conteneurs.
BGP distance 20 < kernel distance 0 → la route kernel gagne → tout le trafic part vers eth0 (mgmt) au lieu de bleaf.
Fix manuel post-deploy :
```bash
for node in spine1 spine2 leaf1 leaf2 leaf3 bleaf; do
  docker exec clab-topo-ebgp-$node ip route del default via 172.20.20.1 dev eth0
done
```

### 4. ARP asymétrique LXC → leaf
Après redeploy propre, le premier ping LXC→GW échouait (ARP pas encore résolu).
Pinguer depuis leaf vers LXC d'abord résout l'ARP dans les deux sens, les pings LXC→GW marchent ensuite.
Pas besoin de fix permanent — se résout au premier trafic depuis leaf.

### 5. SNAT iptables non installé
`apk add iptables` échouait car `2>/dev/null || true` pas interprété par l'exec clab.
Fix : `/bin/sh -c 'apk add --no-cache iptables -q'` dans topology.clab.yml + `iptables -t nat -A ...` comme commande directe (iptables est dans PATH après apk).

## Procédure redeploy propre

```bash
ssh root@10.202.8.220
cd /root/topo-ebgp

# 1. Destroy
containerlab destroy -t topology.clab.yml --cleanup

# 2. Nettoyer veth orphelins si bridges br-lxc1/2/3/br-campus existent encore
ip link delete lxc1 2>/dev/null; ip link delete lxc2 2>/dev/null
ip link delete lxc3 2>/dev/null; ip link delete campus1 2>/dev/null

# 3. Deploy
containerlab deploy -t topology.clab.yml

# 4. Supprimer route mgmt sur tous les nœuds (exec clab ne gère pas || true)
for node in spine1 spine2 leaf1 leaf2 leaf3 bleaf; do
  docker exec clab-topo-ebgp-$node ip route del default via 172.20.20.1 dev eth0 2>/dev/null
done

# 5. Vérifier BGP
docker exec clab-topo-ebgp-spine1 vtysh -c 'show bgp summary'
docker exec clab-topo-ebgp-bleaf vtysh -c 'show bgp summary'

# 6. Test LXC (depuis Proxmox 10.202.8.101)
ssh root@10.202.8.101 'pct exec 213 -- ping -c2 8.8.8.8'
```

## Vérifications rapides

```bash
# BGP spine1 — doit montrer 4 peers Established (leaf1/2/3 + bleaf)
docker exec clab-topo-ebgp-spine1 vtysh -c 'show bgp summary'

# Route default sur leaf1 via bleaf
docker exec clab-topo-ebgp-leaf1 ip route show default

# SNAT actif sur bleaf
docker exec clab-topo-ebgp-bleaf iptables -t nat -L POSTROUTING -n

# LXC internet
ssh root@10.202.8.101 'pct exec 213 -- ping -c2 8.8.8.8'
```

## Fichiers modifiés

| Fichier | Changement |
|---------|-----------|
| `containerlab/topo-ebgp/topology.clab.yml` | bleaf exec : SNAT, default-originate, vxlan Valentin ; exec `/bin/sh -c` wrapper |
| `containerlab/topo-ebgp/configs/bleaf/frr.conf` | BGP AS65080, peers spine1/spine2, default-originate, EVPN VNI 560100 |
| LXC213 `/etc/network/interfaces` (Proxmox) | eth1 192.168.80.10/24 gw .1, eth0 supprimé |
| LXC214 `/etc/network/interfaces` (Proxmox) | eth1 192.168.81.10/24 gw .1, eth0 supprimé |
| LXC215 `/etc/network/interfaces` (Proxmox) | eth1 192.168.82.10/24 gw .1, eth0 supprimé |
| Proxmox LXC config 213/214/215 | `net0` (campus vmbr0) supprimé via `pct set --delete net0` |

## EVPN inter-DC avec Valentin (opérationnel 2026-06-22)

### Résultat final

| Test | Résultat |
|------|---------|
| bleaf Pierre → 172.16.1.1/2/3/4 (hosts Valentin VNI 560100) | ✅ 0% loss ~5ms |
| bleaf Pierre → 172.16.1.254 (anycast GW Arista) | ✅ 0% loss |
| leaf1/2/3 Valentin → 172.16.1.253 (Pierre bleaf) | ✅ 0% loss ~3ms |
| networkutils Valentin → 172.16.1.253 | ✅ 0% loss ~5ms |
| networkutils Valentin → 172.16.2.253 (Pierre VNI 570) | ✅ 0% loss |

### Architecture veth (solution Default Gateway flag)

FRR avec `advertise-svi-ip` sur une SVI (bridge avec IP) génère type-2 avec flag `Default Gateway` → Arista installe en RIB BGP mais **pas dans la VXLAN FDB**.

Solution : modèle veth pair.
```
veth-h0 (IP 172.16.1.253/24, outside br-val)
   ↕
veth-h1 (no IP, master br-val) ← FRR voit le MAC ici
   ↕
br-val ← vxlan560100 (VTEP remote)
```
ARP permanent sur br-val : `ip neigh replace 172.16.1.253 lladdr <MAC-veth-h1> dev br-val nud permanent`
→ FRR génère type-2 pour cette IP sans flag Default Gateway → Arista installe en FDB ✅

### Pourquoi RT export 65899:560 obligatoire

Arista leaf1 Valentin : `route-target import 65899:560` (son propre AS).
Sans `route-target export 65899:560` côté Pierre : routes reçues dans RIB BGP Arista mais **rejetées** à l'import VXLAN FDB.
Fix : exporter les deux RT — `65080:560` (Pierre) ET `65899:560` (Valentin).

### Procédure redeploy avec EVPN

Après `containerlab deploy`, les exec bleaf dans topology.clab.yml :
1. Créent vxlan560100/570100 (`id 560100/570100`, local `10.202.8.253`)
2. Créent br-val/br-val2, attachent les vxlans
3. Créent veth-h0/h1 et veth-h2/h3
4. Assignent IPs sur veth-h0 (172.16.1.253) et veth-h2 (172.16.2.253)
5. Extraient MAC de veth-h1/h3 **dynamiquement** et posent les ARP permanents

FRR démarre avec `advertise-all-vni` + `advertise-svi-ip` → détecte les veth via ARP → génère type-2 → Valentin installe dans FDB → tunnel UP automatiquement.
