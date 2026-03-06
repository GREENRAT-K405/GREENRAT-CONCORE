import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt

# Load the collected data
try:
    df_zmq = pd.read_csv('zeromq_latencies.csv')
    df_zmq['Protocol'] = 'ZeroMQ'
except FileNotFoundError:
    print("Error: zeromq_latencies.csv not found. Please run the experiment first.")
    exit()

# Create the plot
plt.figure(figsize=(10, 7), dpi=100)  # 1000x700 px at 100 dpi

sns.violinplot(
    x='Protocol',
    y='Latency (ms)',
    data=df_zmq,
    palette=['#4CAF50']
)

# Add details to the plot
plt.xlabel('')
plt.ylabel('Round-Trip Latency (ms)', fontsize=16)
plt.grid(True, linestyle='--', alpha=0.6)
plt.xticks(fontsize=14)
plt.yticks(fontsize=14)

plt.tight_layout()

# Save to PDF
plt.savefig('zmq_latency.pdf', format='pdf', dpi=100)
print("Plot saved as 'zmq_latency.pdf'")

# Calculate and print stats for your paper
median_val = df_zmq['Latency (ms)'].median()
mean_val = df_zmq['Latency (ms)'].mean()
std_val = df_zmq['Latency (ms)'].std()

print(f"ZeroMQ Latency Stats:")
print(f"  - Median: {median_val:.4f} ms")
print(f"  - Mean:   {mean_val:.4f} ms")
print(f"  - Std Dev: {std_val:.4f} ms")

plt.show()