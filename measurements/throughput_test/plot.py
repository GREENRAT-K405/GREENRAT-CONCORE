import matplotlib.pyplot as plt
import numpy as np

# --- Enter your collected data here ---
# Example values, replace with your actual measurements
throughput_mediator = 15.7  # messages/sec
throughput_zmq = 4497.8 # messages/sec
# -----------------------------------------

protocols = ['Mediator', 'ZeroMQ']
values = [throughput_mediator, throughput_zmq]
colors = ['#F44336', '#4CAF50']

plt.figure(figsize=(8, 6))
bars = plt.bar(protocols, values, color=colors)

# Add plot details
plt.ylabel('Throughput (Messages/Second)', fontsize=12)
plt.title('Figure 4: Maximum Throughput Comparison', fontsize=16, pad=20)
plt.xticks(fontsize=12)
# Use a logarithmic scale if the difference is very large
plt.yscale('log')
plt.grid(axis='y', linestyle='--', alpha=0.7)

# Add text labels on top of the bars
for bar in bars:
    yval = bar.get_height()
    plt.text(bar.get_x() + bar.get_width()/2.0, yval, f'{yval:,.0f}', va='bottom', ha='center', fontsize=11)

# Save the figure for your paper
plt.savefig('figure4_throughput_comparison.png', dpi=300)
print("Plot saved as 'figure4_throughput_comparison.png'")

plt.show()