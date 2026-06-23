#!/usr/bin/env python3
"""Bench convergence — mesure le temps de bascule (outage) après panne d'un spine.
Pour chaque topo : trouve le spine utilisé par le flux host1->host3, le coupe,
mesure les paquets ping perdus pendant la bascule (= temps de reconvergence).
Pousse convergence_outage_ms{topo} + convergence_loss_pct{topo} (job convergence).
"""
import subprocess, time, re, urllib.request

TOPOS = ["topo-ebgp", "topo-ibgp-rr", "topo-ospf", "topo-mixed"]
PUSHGW = "http://localhost:9091"
PING_INT = 0.05          # 50 ms entre pings -> resolution 50 ms
PING_WINDOW = 20         # s : fenetre totale de ping
DOWN_AT = 5              # s : on coupe le spine apres 5 s
DOWN_FOR = 9             # s : duree de la panne avant restauration
DEST = "192.168.3.2"
SRC = "192.168.1.2"


def sh(c, **k):
    return subprocess.run(c, capture_output=True, text=True, **k)


def deploy(topo):
    sh(["containerlab", "deploy", "-t", f"/root/{topo}/topology.clab.yml", "--reconfigure"])
    time.sleep(35)
    for c in sh(["docker", "ps", "--format", "{{.Names}}"]).stdout.split():
        if f"clab-{topo}-leaf" in c:
            sh(["docker", "exec", c, "sysctl", "-w", "net.ipv4.fib_multipath_hash_policy=1"])


def destroy(topo):
    sh(["containerlab", "destroy", "-t", f"/root/{topo}/topology.clab.yml", "--cleanup"])
    time.sleep(4)


def spine_of_flow(topo):
    """Quel spine le flux host1->host3 traverse ? (nexthop sur leaf1)"""
    leaf1 = f"clab-{topo}-leaf1"
    out = sh(["docker", "exec", leaf1, "ip", "route", "get", DEST, "from", SRC]).stdout
    m = re.search(r"via (10\.0\.1\.\d+)", out)
    if not m:
        # ECMP/loopback : prend la table BGP/OSPF -> 1er nexthop
        out = sh(["docker", "exec", leaf1, "ip", "route", "show", DEST.rsplit('.', 1)[0] + ".0/24"]).stdout
        m = re.search(r"via (10\.0\.1\.\d+)", out)
    if not m:
        return "spine1"  # defaut
    nh = int(m.group(1).split(".")[-1])
    # liens spine1 : .0/.2/.4   spine2 : .6/.8/.10
    return "spine1" if nh <= 4 else "spine2"


def fabric_ifaces(container):
    out = sh(["docker", "exec", container, "ip", "-br", "link"]).stdout
    return [l.split("@")[0].split()[0] for l in out.splitlines()
            if re.match(r"eth[1-9]", l)]


def set_spine(topo, spine, state):
    c = f"clab-{topo}-{spine}"
    for i in fabric_ifaces(c):
        sh(["docker", "exec", c, "ip", "link", "set", i, state])


def push(topo, outage_ms, loss_pct, spine):
    name = topo.replace("topo-", "")
    body = (
        f"# TYPE convergence_outage_ms gauge\n"
        f'convergence_outage_ms{{topo="{name}"}} {outage_ms}\n'
        f"# TYPE convergence_loss_pct gauge\n"
        f'convergence_loss_pct{{topo="{name}"}} {loss_pct}\n'
    ).encode()
    urllib.request.urlopen(urllib.request.Request(
        f"{PUSHGW}/metrics/job/convergence/topo/{name}",
        data=body, method="POST", headers={"Content-Type": "text/plain"}))


print(f"{'topo':12}{'spine tué':>10}{'perdus':>8}{'outage ms':>11}{'loss %':>8}")
for topo in TOPOS:
    deploy(topo)
    host1 = f"clab-{topo}-host1"
    spine = spine_of_flow(topo)

    # ping continu en arriere-plan dans le conteneur host1
    sh(["docker", "exec", host1, "sh", "-c", "rm -f /tmp/ping.txt"])
    subprocess.Popen(["docker", "exec", host1, "sh", "-c",
                      f"ping -i {PING_INT} -w {PING_WINDOW} {DEST} > /tmp/ping.txt 2>&1"])
    time.sleep(DOWN_AT)
    set_spine(topo, spine, "down")      # PANNE
    time.sleep(DOWN_FOR)
    set_spine(topo, spine, "up")        # restauration
    time.sleep(PING_WINDOW - DOWN_AT - DOWN_FOR + 2)

    out = sh(["docker", "exec", host1, "cat", "/tmp/ping.txt"]).stdout
    m = re.search(r"(\d+) packets transmitted, (\d+) (?:packets )?received.*?([\d.]+)% packet loss", out, re.S)
    if m:
        tx, rx, loss = int(m.group(1)), int(m.group(2)), float(m.group(3))
        lost = tx - rx
        outage_ms = round(lost * PING_INT * 1000)
    else:
        tx = rx = lost = 0; loss = 100.0; outage_ms = -1
    push(topo, outage_ms, loss, spine)
    print(f"{topo:12}{spine:>10}{lost:>8}{outage_ms:>11}{loss:>8.1f}")
    destroy(topo)

print("\nDone — poussé job convergence. (outage = paquets perdus x 50 ms)")
