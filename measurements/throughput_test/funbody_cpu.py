# funbody_throughput_test.py (MODIFIED FOR RESOURCE MONITORING)
import time
import concore
import os
import json
import threading
import psutil
import csv

# --- MONITORING FUNCTION (to be run in a separate thread) ---
def monitor_resources(stop_event, output_list):
    """Monitors this script's CPU and memory usage."""
    process = psutil.Process(os.getpid())
    while not stop_event.is_set():
        cpu_percent = process.cpu_percent(interval=0.5)
        memory_mb = process.memory_info().rss / (1024 * 1024)
        output_list.append({'cpu_percent': cpu_percent, 'memory_mb': memory_mb})

print("funbody (Receiver) using ZMQ PULL socket for Throughput & Resource Test.")


TEST_DURATION = 10
message_count = 0
test_started = False
resource_records = []

# --- Start Monitoring ---
stop_monitoring = threading.Event()
monitor_thread = threading.Thread(target=monitor_resources, args=(stop_monitoring, resource_records))
monitor_thread.start()

# --- Main Throughput Test Logic (Unchanged) ---
concore.init_zmq_port(
    port_name=PORT_NAME_B_OUT,
    port_type="bind",
    address="tcp://0.0.0.0:" + PORT_B_OUT, # Bind to all interfaces on the specified port
    socket_type_str="REP"
)

print(f"Receiver waiting for messages on port {PORT_B_OUT}...")
while True:
    message_str = concore.read(PORT_NAME_B_OUT, "stream", "{}")
    if message_str is None: break
    try:
        message_dict = json.loads(message_str)
    except (json.JSONDecodeError, TypeError):
        continue
    if isinstance(message_dict, dict) and 'type' in message_dict:
        if message_dict['type'] == 'control':
            if message_dict['value'] == 'START' and not test_started:
                test_started = True
            elif message_dict['value'] == 'STOP' and test_started:
                break
        elif message_dict['type'] == 'data' and test_started:
            message_count += 1

# --- Stop Monitoring and Save Results ---
stop_monitoring.set()
monitor_thread.join()
concore.terminate_zmq()

if message_count > 0:
    throughput = message_count / TEST_DURATION
    print(f"THROUGHPUT RESULT: {throughput:.2f} messages/second")

if resource_records:
    with open('receiver_usage.csv', 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['cpu_percent', 'memory_mb'])
        writer.writeheader()
        writer.writerows(resource_records)
    print("Receiver resource usage saved to receiver_usage.csv")