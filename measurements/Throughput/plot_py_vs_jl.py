import matplotlib.pyplot as plt

# Throughput values from the benchmark
throughput_python = 5525.76  # Average of 6878 and 6208
throughput_julia = 5800.7

protocols = ['Python ZMQ', 'Julia ZMQ (Initial)']
values = [throughput_python, throughput_julia]
colors = ['#306998', '#9558B2']  # Python Blue, Julia Purple

plt.figure(figsize=(8, 6), dpi=150)
bars = plt.bar(protocols, values, color=colors, width=0.5)

plt.ylabel('Throughput (Messages/Second)', fontsize=14)
plt.title('ZeroMQ IPC Throughput Comparison', fontsize=16, fontweight='bold')
plt.xticks(fontsize=14)
plt.grid(axis='y', linestyle='--', alpha=0.7)

# Add values on top of bars
for bar in bars:
    yval = bar.get_height()
    plt.text(
        bar.get_x() + bar.get_width() / 2.0,
        yval + 100,
        f'{yval:,.0f}',
        va='bottom',
        ha='center',
        fontsize=14,
        fontweight='bold'
    )

plt.tight_layout()
plt.savefig("throughput_comparison_py_vs_jl.png", dpi=150)
print("Saved plot as throughput_comparison_py_vs_jl.png")
