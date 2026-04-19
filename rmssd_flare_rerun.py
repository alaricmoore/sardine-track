#!/usr/bin/env python3
"""
Rerun of the RMSSD pre-flare pattern analysis with post-bugfix data.

Differences from the original chart (rmssd_flare_analysis.png):
- Uses post-commit-79f6806 RMSSD (heartbeat timestamps no longer mixed across series)
- Splits majors / minors / unspecified into separate panels
- Adds day-to-day |ΔRMSSD| instability metric
- Runs Mann-Whitney tests with updated n

Usage:
    /home/alaric/projects/.venv/bin/python rmssd_flare_rerun.py

Outputs a PNG next to the script: rmssd_flare_rerun.png
"""
import csv
import os
from collections import defaultdict
from datetime import datetime, timedelta

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from scipy import stats

CSV = "/home/alaric/projects/sardines-track/backups/biotracking_backup_20260419_124453/daily_observations.csv"
OUT = "/home/alaric/projects/sardines-track/rmssd_flare_rerun.png"

# --- load ---
rows = {}
with open(CSV) as f:
    for r in csv.DictReader(f):
        rows[r["date"]] = r


def tf(v):
    if v in ("", None):
        return None
    try:
        return float(v)
    except ValueError:
        return None


def tb(v):
    if v in ("", None, "0"):
        return 0
    try:
        return 1 if int(v) == 1 else 0
    except ValueError:
        return 0


def dplus(d, n):
    return (datetime.strptime(d, "%Y-%m-%d") + timedelta(days=n)).strftime("%Y-%m-%d")


# --- identify flare CLUSTERS (group adjacent flare days) ---
flare_dates = sorted(d for d, r in rows.items() if tb(r.get("flare_occurred")))
cluster_onsets = []  # (first_date, severity_of_first_day)
i = 0
while i < len(flare_dates):
    onset = flare_dates[i]
    onset_sev = rows[onset].get("flare_severity") or "unspecified"
    # skip the rest of this run of adjacent dates
    j = i + 1
    while j < len(flare_dates) and flare_dates[j] == dplus(flare_dates[j - 1], 1):
        j += 1
    cluster_onsets.append((onset, onset_sev))
    i = j

print(f"Total flare clusters: {len(cluster_onsets)}")
for sev in ("major", "minor", "er_visit", "unspecified"):
    n = sum(1 for _, s in cluster_onsets if s == sev)
    print(f"  {sev}: {n}")

# --- event-align RMSSD around each onset ---
OFFSETS = list(range(-7, 8))


def align(field, group_filter=None):
    """Returns dict {offset: [values]} across all cluster onsets in the group."""
    out = {k: [] for k in OFFSETS}
    for onset_date, sev in cluster_onsets:
        if group_filter and not group_filter(sev):
            continue
        for off in OFFSETS:
            d = dplus(onset_date, off)
            r = rows.get(d)
            if r is None:
                continue
            v = tf(r.get(field))
            if v is not None:
                out[off].append(v)
    return out


GROUPS = {
    "all (n={n})": lambda s: True,
    "major/ER (n={n})": lambda s: s in ("major", "er_visit"),
    "minor (n={n})": lambda s: s == "minor",
}


def group_n(filter_fn):
    return sum(1 for _, s in cluster_onsets if filter_fn(s))


# --- non-flare baseline (days not within ±3 of any flare) ---
flare_set = set(flare_dates)
proximity = set()
for d in flare_dates:
    for off in range(-3, 4):
        proximity.add(dplus(d, off))

baseline_rmssd = [
    tf(r.get("hrv_rmssd"))
    for d, r in rows.items()
    if d not in proximity and tf(r.get("hrv_rmssd")) is not None
]
baseline_sdnn = [
    tf(r.get("hrv"))
    for d, r in rows.items()
    if d not in proximity and tf(r.get("hrv")) is not None
]

base_rmssd_mean = float(np.mean(baseline_rmssd)) if baseline_rmssd else 0
base_rmssd_gmean = float(stats.gmean([x for x in baseline_rmssd if x > 0])) if baseline_rmssd else 0
base_sdnn_mean = float(np.mean(baseline_sdnn)) if baseline_sdnn else 0
base_pct_over_80 = (
    sum(1 for x in baseline_rmssd if x > 80) / len(baseline_rmssd) * 100 if baseline_rmssd else 0
)

print(f"\nNon-flare baseline (excluding ±3 days around any flare):")
print(f"  RMSSD arithmetic mean: {base_rmssd_mean:.1f} ms (n={len(baseline_rmssd)})")
print(f"  RMSSD geometric mean:  {base_rmssd_gmean:.1f} ms")
print(f"  % RMSSD > 80 ms:       {base_pct_over_80:.1f}%")
print(f"  SDNN arithmetic mean:  {base_sdnn_mean:.1f} ms (n={len(baseline_sdnn)})")

# --- compute group aligned means/medians ---
group_data = {}
for label_fmt, filt in GROUPS.items():
    n = group_n(filt)
    label = label_fmt.format(n=n)
    rmssd_aligned = align("hrv_rmssd", filt)
    sdnn_aligned = align("hrv", filt)
    group_data[label] = {
        "filter": filt,
        "n": n,
        "rmssd": rmssd_aligned,
        "sdnn": sdnn_aligned,
        "rmssd_gmean": {
            off: float(stats.gmean([x for x in v if x > 0])) if len(v) > 0 else np.nan
            for off, v in rmssd_aligned.items()
        },
        "rmssd_mean": {
            off: float(np.mean(v)) if v else np.nan for off, v in rmssd_aligned.items()
        },
        "sdnn_mean": {off: float(np.mean(v)) if v else np.nan for off, v in sdnn_aligned.items()},
        "pct_over_80": {
            off: (sum(1 for x in v if x > 80) / len(v) * 100) if v else np.nan
            for off, v in rmssd_aligned.items()
        },
    }

# --- day-to-day instability |Δᵢ| per-cluster per-transition, aggregated by severity ---
def compute_instability(filter_fn):
    deltas_per_transition = {off: [] for off in OFFSETS[:-1]}  # transitions -7->-6 ... +6->+7
    for onset_date, sev in cluster_onsets:
        if not filter_fn(sev):
            continue
        seq = []
        for off in OFFSETS:
            d = dplus(onset_date, off)
            r = rows.get(d)
            v = tf(r.get("hrv_rmssd")) if r else None
            seq.append(v)
        for i in range(len(seq) - 1):
            if seq[i] is not None and seq[i + 1] is not None:
                deltas_per_transition[OFFSETS[i]].append(abs(seq[i + 1] - seq[i]))
    return {off: float(np.mean(v)) if v else np.nan for off, v in deltas_per_transition.items()}


instability = {
    label: compute_instability(info["filter"]) for label, info in group_data.items()
}

# --- Mann-Whitney: day-1 vs day-0 within each group ---
print("\nMann-Whitney U (day -1 vs day 0 RMSSD):")
for label, info in group_data.items():
    a, b = info["rmssd"].get(-1, []), info["rmssd"].get(0, [])
    if len(a) >= 3 and len(b) >= 3:
        u, p = stats.mannwhitneyu(a, b, alternative="two-sided")
        print(f"  {label}: U={u:.1f}, p={p:.3f}, n(-1)={len(a)} n(0)={len(b)}")
    else:
        print(f"  {label}: insufficient n ({len(a)} vs {len(b)})")

# --- plotting ---
plt.rcParams["figure.facecolor"] = "#0f1020"
plt.rcParams["axes.facecolor"] = "#141528"
plt.rcParams["axes.edgecolor"] = "#3a3b5c"
plt.rcParams["axes.labelcolor"] = "#cfcfe0"
plt.rcParams["xtick.color"] = "#9994a8"
plt.rcParams["ytick.color"] = "#9994a8"
plt.rcParams["text.color"] = "#cfcfe0"
plt.rcParams["font.family"] = "serif"

COLORS = {
    "all (n={n})".format(n=group_n(lambda s: True)): "#8ba8e0",
    "major/ER (n={n})".format(n=group_n(lambda s: s in ("major", "er_visit"))): "#e85d5d",
    "minor (n={n})".format(n=group_n(lambda s: s == "minor")): "#e0a050",
}

fig, axes = plt.subplots(3, 2, figsize=(14, 14), gridspec_kw={"height_ratios": [1.2, 1, 1]})
fig.suptitle(
    "RMSSD pre-flare pattern — post-bugfix rerun, severity-split",
    fontsize=14,
    color="#e0e0f0",
    y=0.995,
)

# Panel 1 (top, spans both cols): geometric mean RMSSD by severity
ax0 = plt.subplot2grid((3, 2), (0, 0), colspan=2)
for label, info in group_data.items():
    if info["n"] == 0:
        continue
    y = [info["rmssd_gmean"][off] for off in OFFSETS]
    ax0.plot(OFFSETS, y, marker="o", lw=2, label=label, color=COLORS.get(label, "#888"))
    for off, val in zip(OFFSETS, y):
        if not np.isnan(val):
            ax0.annotate(
                f"{val:.0f}",
                (off, val),
                textcoords="offset points",
                xytext=(0, 6),
                ha="center",
                fontsize=7,
                color=COLORS.get(label, "#888"),
            )
ax0.axhline(base_rmssd_gmean, color="#d4b84a", linestyle="--", alpha=0.7,
            label=f"non-flare baseline ({base_rmssd_gmean:.0f} ms, geo.mean)")
ax0.axvline(0, color="#c94040", alpha=0.4, lw=1)
ax0.set_xticks(OFFSETS)
ax0.set_xlabel("days relative to flare cluster onset")
ax0.set_ylabel("RMSSD geometric mean (ms)")
ax0.set_title("event-aligned RMSSD around flare onset, by severity", color="#e0e0f0")
ax0.legend(loc="upper left", fontsize=8, framealpha=0.2)
ax0.grid(True, alpha=0.15)

# Panel 2 (middle left): % RMSSD > 80 ms
ax1 = axes[1][0]
width = 0.28
for i, (label, info) in enumerate(group_data.items()):
    if info["n"] == 0:
        continue
    y = [info["pct_over_80"][off] for off in OFFSETS]
    x = [off + (i - 1) * width for off in OFFSETS]
    ax1.bar(x, y, width=width, label=label, color=COLORS.get(label, "#888"), alpha=0.85)
ax1.axhline(base_pct_over_80, color="#d4b84a", linestyle="--", alpha=0.7,
            label=f"baseline ({base_pct_over_80:.0f}%)")
ax1.axvline(0, color="#c94040", alpha=0.4, lw=1)
ax1.set_xticks(OFFSETS)
ax1.set_xlabel("days relative to onset")
ax1.set_ylabel("% of readings > 80 ms")
ax1.set_title("% RMSSD > 80 ms by severity", color="#e0e0f0")
ax1.legend(fontsize=7, framealpha=0.2)
ax1.grid(True, alpha=0.15)

# Panel 3 (middle right): day-to-day instability |Δᵢ|
ax2 = axes[1][1]
for label, info in group_data.items():
    if info["n"] == 0:
        continue
    y = [instability[label].get(off, np.nan) for off in OFFSETS[:-1]]
    ax2.plot(OFFSETS[:-1], y, marker="s", lw=2, label=label, color=COLORS.get(label, "#888"))
ax2.axvline(0, color="#c94040", alpha=0.4, lw=1)
ax2.set_xticks(OFFSETS[:-1])
ax2.set_xlabel("day transition (offset → offset+1)")
ax2.set_ylabel("mean |ΔRMSSD| (ms)")
ax2.set_title("day-to-day instability by severity", color="#e0e0f0")
ax2.legend(fontsize=7, framealpha=0.2)
ax2.grid(True, alpha=0.15)

# Panel 4 (bottom left): SDNN control
ax3 = axes[2][0]
for label, info in group_data.items():
    if info["n"] == 0:
        continue
    y = [info["sdnn_mean"][off] for off in OFFSETS]
    ax3.plot(OFFSETS, y, marker="o", lw=2, label=label, color=COLORS.get(label, "#888"))
ax3.axhline(base_sdnn_mean, color="#d4b84a", linestyle="--", alpha=0.7,
            label=f"baseline ({base_sdnn_mean:.1f} ms)")
ax3.axvline(0, color="#c94040", alpha=0.4, lw=1)
ax3.set_xticks(OFFSETS)
ax3.set_xlabel("days relative to onset")
ax3.set_ylabel("SDNN mean (ms)")
ax3.set_title("SDNN control (expect no strong pattern)", color="#e0e0f0")
ax3.legend(fontsize=7, framealpha=0.2)
ax3.grid(True, alpha=0.15)

# Panel 5 (bottom right): individual major/ER traces
ax4 = axes[2][1]
majors = [(d, s) for d, s in cluster_onsets if s in ("major", "er_visit")]
minors = [(d, s) for d, s in cluster_onsets if s == "minor"]
for onset, sev in majors:
    y = []
    for off in OFFSETS:
        v = tf(rows.get(dplus(onset, off), {}).get("hrv_rmssd"))
        y.append(v if v is not None else np.nan)
    ax4.plot(OFFSETS, y, color="#e85d5d", alpha=0.4, lw=1)
for onset, sev in minors:
    y = []
    for off in OFFSETS:
        v = tf(rows.get(dplus(onset, off), {}).get("hrv_rmssd"))
        y.append(v if v is not None else np.nan)
    ax4.plot(OFFSETS, y, color="#e0a050", alpha=0.3, lw=1)
ax4.axvline(0, color="#c94040", alpha=0.4, lw=1)
ax4.set_xticks(OFFSETS)
ax4.set_xlabel("days relative to onset")
ax4.set_ylabel("RMSSD (ms)")
ax4.set_title(f"individual traces — red=major/ER ({len(majors)}), orange=minor ({len(minors)})",
              color="#e0e0f0")
ax4.grid(True, alpha=0.15)

plt.tight_layout()
plt.savefig(OUT, dpi=120, bbox_inches="tight", facecolor="#0f1020")
print(f"\nSaved: {OUT}")
