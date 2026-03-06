import matplotlib.pyplot as plt

throughput_mediator = 15.7     # messages/sec
throughput_zmq = 25432.1       # messages/sec

protocols = ['Mediator', 'ZeroMQ']
values = [throughput_mediator, throughput_zmq]
colors = ['#F44336', '#4CAF50']

# Match exact pixel size: 1000x700 with dpi=100
plt.figure(figsize=(10, 7), dpi=100)

bars = plt.bar(protocols, values, color=colors)

plt.ylabel('Throughput (Messages/Second)', fontsize=18)
plt.xticks(fontsize=16)
plt.yscale('log')
plt.grid(axis='y', linestyle='--', alpha=0.7)

for bar in bars:
    yval = bar.get_height()
    plt.text(
        bar.get_x() + bar.get_width() / 2.0,
        yval,
        f'{yval:,.0f}',
        va='bottom',
        ha='center',
        fontsize=16
    )

plt.tight_layout()

# Save with the same dimensions
plt.savefig("throughput_comparison.pdf", format="pdf", dpi=100)
print("Plot saved as 'throughput_comparison.pdf'")

plt.show()