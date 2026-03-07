# funcall_throughput_test.py (MODIFIED FOR RESOURCE MONITORING)
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
        # Get CPU (as a percentage) and Memory (RSS in MB)
        cpu_percent = process.cpu_percent(interval=0.5)
        memory_mb = process.memory_info().rss / (1024 * 1024)
        output_list.append({'cpu_percent': cpu_percent, 'memory_mb': memory_mb})

print("funcall (Sender) using ZMQ PUSH socket for Throughput & Resource Test.")


TEST_DURATION = 10
message_count = 0
resource_records = []

# --- Start Monitoring ---
stop_monitoring = threading.Event()
monitor_thread = threading.Thread(target=monitor_resources, args=(stop_monitoring, resource_records))
monitor_thread.start()

# --- Main Throughput Test Logic (Unchanged) ---
concore.init_zmq_port(
    port_name=PORT_NAME_IN_A,
    port_type="connect",
    address="tcp://192.168.0.109:" + PORT_IN_A, # Use 127.0.0.1 for local testing
    socket_type_str="REQ"
)
print(f"Sender starting. Will send data for 10 seconds.")
start_signal = json.dumps({"type": "control", "value": "START"})
concore.write(PORT_NAME_IN_A, "stream", start_signal)
time.sleep(1)
start_time = time.perf_counter()
while (time.perf_counter() - start_time) < TEST_DURATION:
    data_message = json.dumps({"type": "data", "value": message_count})
    concore.write(PORT_NAME_IN_A, "stream", data_message)
    message_count += 1
time.sleep(1)
stop_signal = json.dumps({"type": "control", "value": "STOP"})
concore.write(PORT_NAME_IN_A, "stream", stop_signal)
print(f"Sender finished. Sent approximately {message_count} messages.")

# --- Stop Monitoring and Save Results ---
stop_monitoring.set()
monitor_thread.join()
concore.terminate_zmq()

if resource_records:
    with open('sender_usage.csv', 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['cpu_percent', 'memory_mb'])
        writer.writeheader()
        writer.writerows(resource_records)
    print("Sender resource usage saved to sender_usage.csv")