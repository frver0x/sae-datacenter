#!/usr/bin/env python3
"""Bench répétitions — N tirs identiques par topo à charge plateau fixe.
Mesure TCP (1 flux) + UDP 20G (1 flux) -> moyenne, ecart-type, IC95 par topo.
Pousse les moyennes (+ std pour barres d'erreur) vers Pushgateway (job iperf3_avg).
Resultats bruts + stats : /root/results/reps/<topo>.json
"""
import subprocess, json, time, os, statistics as st, urllib.request

TOPOS   = ["topo-ebgp", "topo-ibgp-rr", "topo-ospf", "topo-mixed"]
REPS    = 15
UDP_LOAD= "20G"     # charge plateau (au-dela du genou ~10G)
DUR     = 10        # s par tir
PUSHGW  = "http://localhost:9091"
OUTDIR  = "/root/results/reps"
os.makedirs(OUTDIR, exist_ok=True)


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


def ensure_iperf(c):
    if sh(["docker", "exec", c, "which", "iperf3"]).returncode != 0:
        sh(["docker", "exec", c, "apk", "add", "--no-cache", "iperf3"])


def server_up(srv):
    if sh(["docker", "exec", srv, "pgrep", "-x", "iperf3"]).returncode != 0:
        subprocess.Popen(["docker", "exec", "-d", srv, "iperf3", "-s", "-D"])
        time.sleep(1)


def one(client, udp=False):
    cmd = ["docker", "exec", client, "iperf3", "-c", "192.168.3.2", "-t", str(DUR), "-J"]
    if udp:
        cmd += ["-u", "-b", UDP_LOAD]
    r = sh(cmd, timeout=DUR + 15)
    try:
        d = json.loads(r.stdout)
        if udp:
            s = d["end"]["sum"]
            return s["bits_per_second"] / 1e9, s["lost_percent"]
        e = d["end"]
        return e["sum_received"]["bits_per_second"] / 1e9, e["sum_sent"]["retransmits"]
    except Exception:
        return None, None


def ci95(xs):
    if len(xs) < 2:
        return 0.0
    return 1.96 * st.pstdev(xs) / (len(xs) ** 0.5)


def push(topo, d):
    name = topo.replace("topo-", "")
    body = "".join(
        f'# TYPE {k} gauge\n{k}{{topo="{name}"}} {v}\n' for k, v in d.items()
    )
    urllib.request.urlopen(urllib.request.Request(
        f"{PUSHGW}/metrics/job/iperf3_avg/topo/{name}",
        data=body.encode(), method="POST",
        headers={"Content-Type": "text/plain"}))


summary = {}
for topo in TOPOS:
    print(f"\n{'='*18} {topo} {'='*18}", flush=True)
    deploy(topo)
    srv, cli = f"clab-{topo}-host3", f"clab-{topo}-host1"
    ensure_iperf(srv); ensure_iperf(cli); server_up(srv)

    tcp, retx, udp, loss = [], [], [], []
    for i in range(1, REPS + 1):
        server_up(srv)
        g, rx = one(cli, udp=False)
        if g is not None:
            tcp.append(g); retx.append(rx)
        ug, ul = one(cli, udp=True)
        if ug is not None:
            udp.append(ug); loss.append(ul)
        print(f"  rep {i:2d}/{REPS}  TCP={g if g else 0:5.2f}G  UDP={ug if ug else 0:5.2f}G  loss={ul if ul is not None else 0:.2f}%", flush=True)

    stats = {
        "tcp_mean": round(st.mean(tcp), 3), "tcp_std": round(st.pstdev(tcp), 3), "tcp_ci95": round(ci95(tcp), 3),
        "udp_mean": round(st.mean(udp), 3), "udp_std": round(st.pstdev(udp), 3), "udp_ci95": round(ci95(udp), 3),
        "loss_mean": round(st.mean(loss), 3), "loss_std": round(st.pstdev(loss), 3),
        "retx_mean": round(st.mean(retx), 1), "n": len(tcp),
    }
    summary[topo] = stats
    json.dump({"raw": {"tcp": tcp, "retx": retx, "udp": udp, "loss": loss}, "stats": stats},
              open(f"{OUTDIR}/{topo}.json", "w"), indent=2)
    push(topo, {
        "iperf3_avg_tcp_gbps": stats["tcp_mean"], "iperf3_avg_tcp_gbps_std": stats["tcp_std"],
        "iperf3_avg_udp_gbps": stats["udp_mean"], "iperf3_avg_udp_gbps_std": stats["udp_std"],
        "iperf3_avg_udp_loss_pct": stats["loss_mean"], "iperf3_avg_udp_loss_pct_std": stats["loss_std"],
        "iperf3_avg_tcp_retransmits": stats["retx_mean"],
    })
    print(f"  -> TCP {stats['tcp_mean']}±{stats['tcp_ci95']}G  UDP {stats['udp_mean']}±{stats['udp_ci95']}G  loss {stats['loss_mean']}±{stats['loss_std']}%", flush=True)
    destroy(topo)

print("\n" + "=" * 60)
print(f"{'topo':12}{'TCP G (±IC95)':>20}{'UDP G (±IC95)':>20}{'loss% (±std)':>18}{'RTX':>8}")
for t in TOPOS:
    s = summary[t]
    print(f"{t.replace('topo-',''):12}{s['tcp_mean']:8.2f} ±{s['tcp_ci95']:<6.2f}{s['udp_mean']:11.2f} ±{s['udp_ci95']:<6.2f}{s['loss_mean']:9.3f} ±{s['loss_std']:<6.3f}{int(s['retx_mean']):8d}")
print("\nDone — moyennes poussees (job iperf3_avg), brut dans", OUTDIR)
