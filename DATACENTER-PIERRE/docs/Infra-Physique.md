# Infra Physique — Cisco + Mikrotik + eBGP

> [!info] Groupe 8 — URTADO Pierre · SAE4D01 · état au 2026-06-17
> Routeur perso C8000V-G8 (AS65080) + Mikrotik (AS65081) en leaf.
> Tout le monde sur le L2 partagé campus `10.202.0.0/16`. eBGP entre groupes.

---

## Topologie physique

```mermaid
graph TB
    subgraph MINE["🟦 Mon infra — Groupe 8"]
        MIK["🟧 Mikrotik<br/>AS65081<br/>172.80.0.1/30<br/>annonce 172.17.0.0/24<br/>default → 172.80.0.2"]
        CIS["🟦 Cisco C8000V-G8<br/>AS65080<br/>Gi2 172.80.0.2/30<br/>Gi1 10.202.8.253/16<br/>Lo0 172.80.255.1/32"]
        SRV["⚪ 172.17.0.0/24<br/>derrière Mikrotik"]
        SRV --- MIK
        MIK -->|"172.80.0.0/30<br/>lien P2P"| CIS
    end

    LAN{{"🟩 L2 partagé campus<br/>10.202.0.0/16<br/>(flat, tous les groupes)"}}

    CIS ===|"Gi1"| LAN

    subgraph PEERS["🟪 Voisins eBGP (autres groupes)"]
        C1["Cisco collègue<br/>AS65001<br/>Gi2 10.202.1.12/16<br/>Lo0 10.255.255.2<br/>annonce 10.202.0.0/16 + 172.20.1.0/24"]
        C60["AS65060<br/>10.202.60.22 — UP"]
        C14["AS65014<br/>10.202.0.227 — down"]
        C70["AS65070 — down"]
        C82["AS65082 — down"]
    end

    LAN === C1
    LAN === C60
    LAN -.-> C14
    LAN -.-> C70
    LAN -.-> C82

    style MIK fill:#ff8c00,color:#000
    style CIS fill:#1e90ff,color:#fff
    style LAN fill:#2ecc71,color:#000
    style C1 fill:#9b59b6,color:#fff
    style C60 fill:#9b59b6,color:#fff
```

---

## Sessions eBGP — mon Cisco (AS65080)

| Voisin | AS | IP peer | État | Préfixes reçus |
|--------|----|---------|------|----------------|
| Collègue | 65001 | 10.202.1.12 | Established | 10.202.0.0/16, 172.20.1.0/24 |
| — | 65060 | 10.202.60.22 | Established | — |
| Mikrotik | 65081 | 172.80.0.1 | Established | 172.17.0.0/24 |
| — | 65014 | 10.202.0.227 | ❌ down | — |
| — | 65070 | — | ❌ down | — |
| — | 65082 | — | ❌ down | — |

---

## Ce que j'annonce (AS65080)

| Préfixe | Origine | Poussé aux peers UP |
|---------|---------|---------------------|
| `172.80.0.0/30` | lien Cisco↔Mikrotik | |
| `172.80.255.1/32` | ma Loopback0 | |
| `172.17.0.0/24` | appris du Mikrotik (AS65081) | |

---

## Plan d'adressage

| Élément | IP | Rôle |
|---------|-----|------|
| Cisco Gi1 | `10.202.8.253/16` | uplink campus (L2 partagé) |
| Cisco Gi2 | `172.80.0.2/30` | lien vers Mikrotik |
| Cisco Lo0 | `172.80.255.1/32` | IP stable hors zone partagée |
| Mikrotik | `172.80.0.1/30` | leaf |
| Derrière Mikrotik | `172.17.0.0/24` | services |

---

## Notes routage

- Lien renuméroté `172.20.0.0/30` → `172.80.0.0/30` (Mikrotik = `.1`, Cisco = `.2`).
- Mikrotik a une default route `0.0.0.0/0 → 172.80.0.2` = chemin retour vers tout l'extérieur.
- Loopback `172.80.255.1/32` hors `10.202.0.0/16` → pas shadowée par le /16 connecté de tout le monde → joignable de partout (longest-match /32 bat /16).
- Piège du /16 partagé : sourcer un ping depuis une IP `10.202.x.x` = shadowée par le connecté → préférer IP annoncée hors zone (loopback) ou interface du L2 partagé directement joignable.

---

*Généré 2026-06-17 — données live depuis Cisco 10.202.8.253*
