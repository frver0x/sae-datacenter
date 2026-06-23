# Documentation — SAE4D01 DevCloud

Comptes-rendus, fiche oral et notes de la SAÉ Datacenters (Groupe 8 — URTADO Pierre).

## Livrables

| Fichier | Contenu |
| --- | --- |
| [CR-COMPLET.md](CR-COMPLET.md) | **Compte rendu complet** — fabric leaf-spine en 4 technos (eBGP, iBGP-RR, OSPF, mixed) + EVPN/VXLAN, benchmark chiffré, supervision Grafana |
| [DEMARCHE.md](DEMARCHE.md) | Démarche projet / méthodologie |
| [FICHE-ORAL.md](FICHE-ORAL.md) | Fiche de préparation à l'oral |
| [Infra-Physique.md](Infra-Physique.md) | Schéma infra physique — Cisco C8000V + Mikrotik + eBGP campus |
| [Leaf-Spine.md](Leaf-Spine.md) | CR de séance — fabric leaf-spine containerlab |
| [pdf/](pdf/) | Versions PDF des livrables principaux |

## Notes de travail

- [notes/SAE4D01-PierreURTADO.md](notes/SAE4D01-PierreURTADO.md) — note master (vault Obsidian) : vocabulaire, configs, captures. Secrets retirés.
- [notes/working-evpn-lab.md](notes/working-evpn-lab.md) — état du lab topo-ebgp + bleaf + LXC.
- [notes/working-grafana-lxc.md](notes/working-grafana-lxc.md) — déploiement Grafana sur LXC.
- `notes/attachments/` — captures référencées par la note master.

## Journaux Notion (séances)

Pages Notion du groupe 8 exportées en markdown (images dans `notion/images/`) :

- [notion/pierre-c8000v-setup.md](notion/pierre-c8000v-setup.md) — déploiement routeur virtuel Cisco C8000V.
- [notion/pierre-containerlab-leaf-spine-15-06-2026.md](notion/pierre-containerlab-leaf-spine-15-06-2026.md) — fabric leaf-spine containerlab (cEOS + FRR).
- [notion/pierre-bgplab-evpn-vxlan-lab1.md](notion/pierre-bgplab-evpn-vxlan-lab1.md) — labs VXLAN/EVPN (single + multi-VTEP).
- [notion/pierre-ha-ebgp-physique.md](notion/pierre-ha-ebgp-physique.md) — eBGP physique Cisco + Mikrotik.
- [notion/sae4d01-cr-reseau-cisco-mikrotik-ebgp.md](notion/sae4d01-cr-reseau-cisco-mikrotik-ebgp.md) — CR réseau Cisco + Mikrotik + diagnostic flap LAN partagé.
