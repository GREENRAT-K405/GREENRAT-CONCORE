import concore
import time
import os
import psutil
import sys

# --- Measurement & Script Configuration ---
concore.delay = 0.01
init_simtime_u = "[0.0, 0.0, 0.0]"
init_simtime_ym = "[0.0, 0.0, 0.0]"

# --- Measurement Initialization ---
min_latency = float('inf')
max_latency = 0.0
total_latency = 0.0
message_count = 0
total_bytes = 0
process = psutil.Process(os.getpid())
overall_start_time = time.monotonic()
wallclock1 = time.perf_counter()

# --- Main Script Logic ---
u = concore.initval(init_simtime_u)
curr = 0.0
max_value = 100.0
iteration_limit = 15 # Safety break
iteration = 0

print("cpymax_test.py started...")

# Initiate the loop by writing an initial value
print(f"ym=N/A u={u[0]:.2f} (initial)")
concore.write(1, "u", u)

while curr < max_value and iteration < iteration_limit:
    # Wait for the processed value to come back
    while concore.unchanged():
        ym = concore.read(1, "ym", init_simtime_ym)
    
    wallclock2 = time.perf_counter()
    latency_ms = (wallclock2 - wallclock1) * 1000 # Round-trip time in milliseconds

    # Update metrics
    message_count += 1
    total_bytes += sys.getsizeof(ym)
    min_latency = min(min_latency, latency_ms)
    max_latency = max(max_latency, latency_ms)
    total_latency += latency_ms

    # Prepare next value
    u[0] = ym[0]
    curr = u[0]
    print(f"ym={ym[0]:.2f} u={u[0]:.2f} | Latency: {latency_ms:.2f} ms")
    
    # Write the value back into the loop
    concore.write(1, "u", u)
    wallclock1 = time.perf_counter() # Reset timer for next round-trip
    iteration += 1

# --- Finalize and Report Measurements ---
overall_end_time = time.monotonic()
total_duration = overall_end_time - overall_start_time
cpu_usage = process.cpu_percent() / total_duration if total_duration > 0 else 0
avg_latency = total_latency / message_count if message_count > 0 else 0

print("\n" + "="*30)
print("--- CPYMAX_TEST: FINAL RESULTS ---")
print(f"Total loop iterations:    {message_count}")
print(f"Total data received:      {total_bytes / 1024:.4f} KB")
print(f"Total execution time:     {total_duration:.4f} seconds")
print("-" * 30)
print(f"Min round-trip latency:   {min_latency:.2f} ms")
print(f"Avg round-trip latency:   {avg_latency:.2f} ms")
print(f"Max round-trip latency:   {max_latency:.2f} ms")
print("-" * 30)
print(f"Approximate CPU usage:    {cpu_usage:.2f}%")
print(f"concore retry count:      {concore.retrycount}")
print("="*30)
