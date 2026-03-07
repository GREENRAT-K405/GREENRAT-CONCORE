"""
compare_latency.py
==================
Parses per-iteration latency lines from the cpymax node's concoreout.txt
in both test_py_bench and test_jl_bench, then produces:
  - py_latencies.csv        (raw latency-per-iteration for Python)
  - jl_latencies.csv        (raw latency-per-iteration for Julia)
  - latency_comparison.png  (violin + box overlay, side-by-side)
  - a printed summary table

Expected log-line format (from cpymax_test.py / cpymax_test.jl):
  ym=<val> u=<val> | Latency: <ms> ms

Run from the measurements/ directory:
  python compare_latency.py
"""

import re
import os
import sys
import csv
import statistics

# ---------------------------------------------------------------------------
# Paths — relative to measurements/
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

PY_LOG   = os.path.join(SCRIPT_DIR, "test_py_bench", "CZ", "concoreout.txt")
JL_LOG   = os.path.join(SCRIPT_DIR, "test_jl_bench", "CZ", "concoreout.txt")

PY_CSV   = os.path.join(SCRIPT_DIR, "py_latencies.csv")
JL_CSV   = os.path.join(SCRIPT_DIR, "jl_latencies.csv")
PNG_OUT  = os.path.join(SCRIPT_DIR, "latency_comparison.png")
PDF_OUT  = os.path.join(SCRIPT_DIR, "latency_comparison.pdf")

# ---------------------------------------------------------------------------
# Parser
# ---------------------------------------------------------------------------
LATENCY_RE = re.compile(r"Latency:\s*([\d.]+)\s*ms", re.IGNORECASE)

def parse_latencies(filepath):
    """Return a list of float latency values (ms) from a concoreout.txt."""
    latencies = []
    if not os.path.exists(filepath):
        print(f"  [WARN] File not found: {filepath}")
        return latencies
    with open(filepath, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = LATENCY_RE.search(line)
            if m:
                latencies.append(float(m.group(1)))
    return latencies

# ---------------------------------------------------------------------------
# CSV writer
# ---------------------------------------------------------------------------
def write_csv(filepath, values, header="Latency (ms)"):
    with open(filepath, "w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow([header])
        for v in values:
            writer.writerow([f"{v:.4f}"])
    print(f"  Saved {len(values)} rows → {os.path.relpath(filepath, SCRIPT_DIR)}")

# ---------------------------------------------------------------------------
# Summary printer
# ---------------------------------------------------------------------------
def print_summary(label, values):
    if not values:
        print(f"  {label}: no data")
        return
    print(f"\n  {'─'*40}")
    print(f"  {label}  (n={len(values)} iterations)")
    print(f"  {'─'*40}")
    print(f"  Min latency : {min(values):.2f} ms")
    print(f"  Avg latency : {statistics.mean(values):.2f} ms")
    print(f"  Median      : {statistics.median(values):.2f} ms")
    print(f"  Max latency : {max(values):.2f} ms")
    print(f"  Std dev     : {statistics.stdev(values):.2f} ms" if len(values) > 1 else "")

# ---------------------------------------------------------------------------
# Plot
# ---------------------------------------------------------------------------
def make_plot(py_vals, jl_vals):
    try:
        import matplotlib.pyplot as plt
        import matplotlib.patches as mpatches
        import numpy as np
    except ImportError:
        print("\n  [WARN] matplotlib not installed — skipping plot.")
        print("         Install with:  pip install matplotlib")
        return

    datasets  = []
    labels    = []
    colors    = []

    if py_vals:
        datasets.append(py_vals)
        labels.append("Python\n(file I/O)")
        colors.append("#1976D2")   # blue

    if jl_vals:
        datasets.append(jl_vals)
        labels.append("Julia\n(file I/O)")
        colors.append("#43A047")   # green

    if not datasets:
        print("  [WARN] No data to plot.")
        return

    fig, ax = plt.subplots(figsize=(max(6, 3.5 * len(datasets)), 7))

    # Violin
    parts = ax.violinplot(datasets, positions=range(1, len(datasets)+1),
                          showmedians=False, showextrema=False)
    for pc, color in zip(parts["bodies"], colors):
        pc.set_facecolor(color)
        pc.set_alpha(0.55)
        pc.set_edgecolor("black")
        pc.set_linewidth(1.2)

    # Box overlay
    bp = ax.boxplot(datasets, positions=range(1, len(datasets)+1),
                    widths=0.12, patch_artist=True,
                    medianprops=dict(color="white", linewidth=2.5),
                    boxprops=dict(facecolor="black", alpha=0.6),
                    whiskerprops=dict(color="black"),
                    capprops=dict(color="black"),
                    flierprops=dict(marker="o", markerfacecolor="grey",
                                   markersize=3, alpha=0.4, linestyle="none"))

    # Styling
    ax.set_xticks(range(1, len(datasets)+1))
    ax.set_xticklabels(labels, fontsize=14)
    ax.set_ylabel("Round-Trip Latency (ms)", fontsize=14)
    ax.set_title("Concore File-Only Communication\nLatency: Python vs Julia", fontsize=15, fontweight="bold")
    ax.grid(True, axis="y", linestyle="--", linewidth=0.6, color="grey", alpha=0.6)
    ax.spines[["top", "right"]].set_visible(False)

    # Stat annotations
    for i, (vals, color) in enumerate(zip(datasets, colors), start=1):
        med = statistics.median(vals)
        avg = statistics.mean(vals)
        ax.annotate(f"med={med:.1f}", xy=(i, med), xytext=(i + 0.22, med),
                    fontsize=9, color="black",
                    arrowprops=dict(arrowstyle="-", color="grey", lw=0.8))

    patch_legend = [mpatches.Patch(facecolor=c, alpha=0.55, label=l.replace("\n", " "))
                    for c, l in zip(colors, labels)]
    ax.legend(handles=patch_legend, fontsize=11, loc="upper right")

    plt.tight_layout()
    plt.savefig(PNG_OUT, dpi=150)
    plt.savefig(PDF_OUT, format="pdf")
    print(f"\n  Plot saved → {os.path.relpath(PNG_OUT, SCRIPT_DIR)}")
    print(f"  Plot saved → {os.path.relpath(PDF_OUT, SCRIPT_DIR)}")
    plt.show()

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("=" * 50)
    print(" Concore Latency Comparison: Python vs Julia")
    print(" File-Only Communication Benchmark")
    print("=" * 50)

    print(f"\nParsing Python log:  {os.path.relpath(PY_LOG, SCRIPT_DIR)}")
    py_vals = parse_latencies(PY_LOG)

    print(f"Parsing Julia log:   {os.path.relpath(JL_LOG, SCRIPT_DIR)}")
    jl_vals = parse_latencies(JL_LOG)

    if not py_vals and not jl_vals:
        print("\n[ERROR] No latency data found in either log file.")
        print("Make sure you have run both benchmarks first:")
        print("  measurements\\test_py_bench\\run.bat")
        print("  measurements\\test_jl_bench\\run.bat")
        print("\nThe latency lines are printed by cpymax_test (the CZ node).")
        sys.exit(1)

    print(f"\nFound {len(py_vals)} Python samples, {len(jl_vals)} Julia samples.")

    # Write CSVs
    print("\nWriting CSVs...")
    if py_vals:
        write_csv(PY_CSV, py_vals)
    if jl_vals:
        write_csv(JL_CSV, jl_vals)

    # Summaries
    print_summary("Python  (file I/O)", py_vals)
    print_summary("Julia   (file I/O)", jl_vals)

    # Speedup / comparison
    if py_vals and jl_vals:
        py_med = statistics.median(py_vals)
        jl_med = statistics.median(jl_vals)
        ratio  = py_med / jl_med if jl_med else float("inf")
        print(f"\n  {'─'*40}")
        if ratio >= 1:
            print(f"  Julia is {ratio:.2f}x FASTER than Python (median)")
        else:
            print(f"  Python is {1/ratio:.2f}x FASTER than Julia (median)")
        print(f"  {'─'*40}")

    # Plot
    print("\nGenerating plot...")
    make_plot(py_vals, jl_vals)

    print("\nDone.")

if __name__ == "__main__":
    main()
