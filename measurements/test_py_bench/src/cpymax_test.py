import concore
import time
import os
import psutil
import sys

# --- Script Configuration ---
# maxtime controls number of iterations (each pmpymax write increments simtime by 1)
concore.delay = 0.01
concore.default_maxtime(1000)   # 1000 round trips

init_simtime_u  = "[0.0, 0.0, 0.0]"
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

print("cpymax_test.py started...")

# Wait for first ym to arrive (pmpymax starts the chain with delta=1)
while concore.simtime < concore.maxtime:
    while concore.unchanged():
        ym = concore.read(1, "ym", init_simtime_ym)

    wallclock2 = time.perf_counter()
    latency_ms = (wallclock2 - wallclock1) * 1000

    # Update metrics
    message_count += 1
    total_bytes += sys.getsizeof(ym)
    min_latency = min(min_latency, latency_ms)
    max_latency = max(max_latency, latency_ms)
    total_latency += latency_ms

    # Prepare and send next value
    u[0] = ym[0] + 1
    print(f"ym={ym[0]:.2f} u={u[0]:.2f} | Latency: {latency_ms:.2f} ms")

    concore.write(1, "u", u)
    wallclock1 = time.perf_counter()

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
