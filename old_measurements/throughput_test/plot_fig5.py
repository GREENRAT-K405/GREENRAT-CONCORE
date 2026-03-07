import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt

# Load all data and calculate averages
try:
    avg_cpu_sender_zmq = pd.read_csv('sender_zmq_usage.csv')['cpu_percent'].mean()
    avg_mem_sender_zmq = pd.read_csv('sender_zmq_usage.csv')['memory_mb'].mean()
    
    # In a real test, you would also measure the receiver. For simplicity, we plot sender.
    # avg_cpu_receiver_zmq = pd.read_csv('receiver_zmq_usage.csv')['cpu_percent'].mean()
    # avg_mem_receiver_zmq = pd.read_csv('receiver_zmq_usage.csv')['memory_mb'].mean()

    # Create placeholder data for Mediator until you run the test
    avg_cpu_sender_mediator = 25.5 # Example value
    avg_mem_sender_mediator = 60.2   # Example value

except FileNotFoundError:
    print("One or more CSV files not found. Using placeholder data.")
    # Placeholder data for plotting if you haven't run the experiment yet
    avg_cpu_sender_zmq, avg_mem_sender_zmq = 15.0, 45.0
    avg_cpu_sender_mediator, avg_mem_sender_mediator = 25.5, 60.2

# Prepare data for plotting
data = {
    'Protocol': ['Mediator', 'ZeroMQ', 'Mediator', 'ZeroMQ'],
    'Metric': ['CPU Usage (%)', 'CPU Usage (%)', 'Memory Usage (MB)', 'Memory Usage (MB)'],
    'Value': [avg_cpu_sender_mediator, avg_cpu_sender_zmq, avg_mem_sender_mediator, avg_mem_sender_zmq]
}
df_plot = pd.DataFrame(data)

# Create the grouped bar chart
plt.figure(figsize=(10, 7))
sns.barplot(x='Metric', y='Value', hue='Protocol', data=df_plot, palette={'Mediator': '#F44336', 'ZeroMQ': '#4CAF50'})

plt.title('Figure 5: Resource Utilization During Throughput Test (Sender)', fontsize=16)
plt.xlabel('Performance Metric', fontsize=12)
plt.ylabel('Average Usage', fontsize=12)
plt.legend(title='Protocol')
plt.grid(axis='y', linestyle='--', alpha=0.7)

plt.show()