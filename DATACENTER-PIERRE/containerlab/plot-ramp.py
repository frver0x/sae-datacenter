#!/usr/bin/env python3
"""Plot offered-vs-received + loss% par topo -> trouve visuellement la saturation.
Usage: python3 plot-ramp.py [dossier_csv]   (defaut /root/results/ramp)
Sort: /root/results/ramp/saturation.png
"""
import csv, glob, os, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

D = sys.argv[1] if len(sys.argv) > 1 else "/root/results/ramp"
files = sorted(glob.glob(os.path.join(D, "*.csv")))
if not files:
    sys.exit(f"aucun CSV dans {D}")

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))
for f in files:
    name = os.path.splitext(os.path.basename(f))[0]
    off, recv, loss = [], [], []
    with open(f) as fh:
        for r in csv.DictReader(fh):
            off.append(float(r["offered_gbps"]))
            recv.append(float(r["recv_gbps"]))
            loss.append(float(r["loss_pct"]))
    ax1.plot(off, recv, marker="o", label=name)
    ax2.plot(off, loss, marker="o", label=name)

# ligne y=x (ideal sans perte)
m = max(max(float(r["offered_gbps"]) for r in csv.DictReader(open(f))) for f in files)
ax1.plot([0, m], [0, m], "k--", alpha=0.3, label="ideal (0 perte)")

ax1.set_xlabel("Debit offert (Gbit/s)")
ax1.set_ylabel("Debit recu (Gbit/s)")
ax1.set_title("Offert vs Recu — plateau = saturation")
ax1.legend(); ax1.grid(alpha=0.3)

ax2.set_xlabel("Debit offert (Gbit/s)")
ax2.set_ylabel("Perte (%)")
ax2.set_title("Perte vs charge — montee = decroche")
ax2.legend(); ax2.grid(alpha=0.3)

out = os.path.join(D, "saturation.png")
plt.tight_layout(); plt.savefig(out, dpi=120)
print("ecrit:", out)
