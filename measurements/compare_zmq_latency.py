"""
compare_zmq_latency.py
======================
Parses per-iteration latency lines from Node A's concoreout.txt
in both ZMQ_PY_bench and ZMQ_JL_bench, then produces:
  - zmq_py_latencies.csv    (raw latency-per-iteration for Python ZMQ)
  - zmq_jl_latencies.csv    (raw latency-per-iteration for Julia ZMQ)
  - zmq_latency_comparison.png (violin + box overlay, side-by-side)
  - a printed summary table

Expected log-line format:
  Node A: Received final value ... | Latency: <ms> ms
"""

import re
import os
import sys
import csv
import statistics

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

PY_LOG   = os.path.join(SCRIPT_DIR, "zmq_py_benchmark", "F1", "concoreout.txt")
JL_LOG   = os.path.join(SCRIPT_DIR, "zmq_jl_benchmark", "F1", "concoreout.txt")

PY_CSV   = os.path.join(SCRIPT_DIR, "zmq_py_latencies.csv")
JL_CSV   = os.path.join(SCRIPT_DIR, "zmq_jl_latencies.csv")
PNG_OUT  = os.path.join(SCRIPT_DIR, "zmq_latency_comparison.png")
PDF_OUT  = os.path.join(SCRIPT_DIR, "zmq_latency_comparison.pdf")

LATENCY_RE = re.compile(r"\| Latency:\s*([\d.]+)\s*ms", re.IGNORECASE)

def parse_latencies(filepath):
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

def write_csv(filepath, values, header="Latency (ms)"):
    with open(filepath, "w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow([header])
        for v in values:
            writer.writerow([f"{v:.4f}"])
    print(f"  Saved {len(values)} rows → {os.path.relpath(filepath, SCRIPT_DIR)}")

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

def make_plot(py_vals, jl_vals):
    try:
        import matplotlib.pyplot as plt
        import matplotlib.patches as mpatches
    except ImportError:
        print("\n  [WARN] matplotlib not installed — skipping plot.")
        return

    datasets, labels, colors = [], [], []

    if py_vals:
        datasets.append(py_vals)
        labels.append("Python\n(ZeroMQ)")
        colors.append("#1976D2")

    if jl_vals:
        datasets.append(jl_vals)
        labels.append("Julia\n(ZeroMQ)")
        colors.append("#43A047")

    if not datasets:
        return

    fig, ax = plt.subplots(figsize=(max(6, 3.5 * len(datasets)), 7))

    parts = ax.violinplot(datasets, positions=range(1, len(datasets)+1),
                          showmedians=False, showextrema=False)
    for pc, color in zip(parts["bodies"], colors):
        pc.set_facecolor(color)
        pc.set_alpha(0.55)
        pc.set_edgecolor("black")
        pc.set_linewidth(1.2)

    ax.boxplot(datasets, positions=range(1, len(datasets)+1),
               widths=0.12, patch_artist=True,
               medianprops=dict(color="white", linewidth=2.5),
               boxprops=dict(facecolor="black", alpha=0.6),
               whiskerprops=dict(color="black"),
               capprops=dict(color="black"),
               flierprops=dict(marker="o", markerfacecolor="grey",
                              markersize=3, alpha=0.4, linestyle="none"))

    ax.set_xticks(range(1, len(datasets)+1))
    ax.set_xticklabels(labels, fontsize=14)
    ax.set_ylabel("Round-Trip Latency (ms)", fontsize=14)
    ax.set_title("Concore ZeroMQ Communication\nLatency: Python vs Julia", fontsize=15, fontweight="bold")
    ax.grid(True, axis="y", linestyle="--", linewidth=0.6, color="grey", alpha=0.6)
    ax.spines[["top", "right"]].set_visible(False)

    for i, (vals, color) in enumerate(zip(datasets, colors), start=1):
        med = statistics.median(vals)
        ax.annotate(f"med={med:.2f}", xy=(i, med), xytext=(i + 0.22, med),
                    fontsize=9, color="black",
                    arrowprops=dict(arrowstyle="-", color="grey", lw=0.8))

    patch_legend = [mpatches.Patch(facecolor=c, alpha=0.55, label=l.replace("\n", " "))
                    for c, l in zip(colors, labels)]
    ax.legend(handles=patch_legend, fontsize=11, loc="upper right")

    plt.tight_layout()
    plt.savefig(PNG_OUT, dpi=150)
    plt.savefig(PDF_OUT, format="pdf")
    print(f"\n  Plot saved → {os.path.relpath(PNG_OUT, SCRIPT_DIR)}")

def main():
    print("=" * 50)
    print(" Concore ZMQ Latency Comparison: Python vs Julia")
    print("=" * 50)

    py_vals = parse_latencies(PY_LOG)
    jl_vals = parse_latencies(JL_LOG)

    if not py_vals and not jl_vals:
        print("\n[ERROR] No latency data found in either ZMQ log file.")
        print("Run both benchmarks first:")
        print("  measurements\\ZMQ_PY_bench\\run.bat")
        print("  measurements\\ZMQ_JL_bench\\run.bat")
        sys.exit(1)

    print(f"\nFound {len(py_vals)} Python samples, {len(jl_vals)} Julia samples.")

    if py_vals: write_csv(PY_CSV, py_vals)
    if jl_vals: write_csv(JL_CSV, jl_vals)

    print_summary("Python  (ZeroMQ)", py_vals)
    print_summary("Julia   (ZeroMQ)", jl_vals)

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

    make_plot(py_vals, jl_vals)

if __name__ == "__main__":
    main()
