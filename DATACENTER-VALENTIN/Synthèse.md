# 1. Synthèse

Durant cette SAE, j’ai conçu un fabric leaf-spine sur Arista cEOS via netlab/containerlab. J’ai décomposé le fabric en 2 spines, 3 leafs dont un border-leaf (bleaf). J'ai fait le choix d'un **iBGP en AS unique (65899)** sur tout le fabric, avec les spines configurés en route-reflectors pour l'underlay (AF IPv4) et l'overlay (AF EVPN) (AF = Address Family).Pierre a utilisé **eBGP** pour faire du **multi-AS**, qui est le design réellement recommandé en datacenter moderne car chaque équipement porte son propre numéro d’AS, le next-hop est réécrit automatiquement à chaque saut (contrairement à iBGP), il n'y a pas de problème de split-horizo, ni besoin de route-reflectors….

J'ai tout de même choisi iBGP pour expérimenter une techno différente de la sienne et comprendre les contraintes associées, notamment le fait que l'iBGP impose  `next-hop-self` sur les spines et la configuration explicite des sessions RR. En production, c’est compliqué de maintenir de telles configurations manuelles.

Le plan de contrôle repose sur EVPN (MP-BGP activé par l'`address-family evpn`), le plan de données sur VXLAN (VNI 560100 pour le VLAN 560 "web"). Pour le transport, j’ai utilisé des route-targets et `send-community extended` sur chaque session iBGP.

### Problèmes rencontrés et résolus

---

1.  J'ai dû ajouter un peering iBGP direct entre spine1 et **spine2** (10.255.3.0/30) car sans lien entre les deux RR, spine2 n'apprenait pas les préfixes locaux annoncés uniquement par spine1 (les sous-réseaux de monitoring), puisqu'un RR ne réfléchit pas les routes entre clients d'un autre RR. Ce mécanisme m’a permis de réaliser du monitoring avec sFlow sur l’ensemble du Fabric.
2.  Pour le monitoring, j'ai installé un grafana, un prometheus et un sflowrt directement reliés à spine1 via des liens point-à-point (10.255.9-11.0/30) plutôt qu'avec des VLANS,. J’ai annoncé ces préfixes via network sur spine1. Le sFlow a nécessité une configuration spécifique sur chaque routeur : 
    
    ```yaml
          conf t
          sflow source-interface Loopback0
          sflow vrf default destination 10.255.9.2 6343
          sflow sample 1000
          sflow run
          write memory
    ```
    
    J’ai aussi rencontré divers problèmes lors de la mise en place du monitoring, échange par inadvertance des adresses de Loopback entre les routeurs…
    
3.  Côté hosts, dans le fichier `topology.yml`j'ai utilisé `routing.static` avec `nexthop.node` pour injecter les routes par défaut car les conteneurs n'ont pas les droits root pour le faire manuellement. J'ai construit des images via des Dockerfile custom (prometheus-sae, sflowrt-sae avec browse-flows/browse-metrics installés par avance) pour éviter la reconfiguration à chaque déploiement et éviter les incidents liés aux permissions (ne pas pouvoir faire un apt update dans un containeur par exemple). En complément, j’ai mis en place du **VARP** (gateway anycast 172.16.1.254, MAC virtuelle partagée) entre leaf1 et leaf2 pour le VLAN 560.

### Échecs

1. Mon principal échec est la mise en place du NAT.Le SNAT fonctionnait sous cEOS 4.33.1F. Pour tenter de résoudre le souci, je suis passé à la version 4.36.1F de cEOS, la commande est devenue % Unrecognized command (plus reconnue), y compris sous SVI. J’en ai conclu que le NAT n’était pas disponible dans la version conteneurisé de cEOS.
2. Mon second échec est que je n’ai pas réussi à accèder aux services conteneurisés dans le fabric en externe. L’accès aux conteneurs en interne (localhost:3000, etc.) fonctionne. J’ai utilisé tcpdump sur ens18 (interface sur la salle) et il montre que les SYN arrivent bien, le binding Docker est correct (0.0.0.0), le conteneur tourne, mais aucun SYN-ACK ne repart.
