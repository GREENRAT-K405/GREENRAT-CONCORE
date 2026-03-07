import concore
import time
import os
import psutil
import sys

# --- Script Configuration ---
concore.delay = 0.01
concore.default_maxtime(1000)   # must match cpymax's maxtime

init_simtime_u  = "[0.0, 0.0, 0.0]"
init_simtime_ym = "[0.0, 0.0, 0.0]"

# --- Measurement Initialization ---
process = psutil.Process(os.getpid())
start_time = time.monotonic()
message_count = 0
total_bytes = 0

# --- Main Script Logic ---
ym = concore.initval(init_simtime_ym)

print("pmpymax_test.py started...")

# pmpymax drives the pipeline: it writes first with delta=1 to kick off simtime
# Then on each tick it reads u, increments, and writes ym (advancing simtime)
while concore.simtime < concore.maxtime:
    while concore.unchanged():
        u = concore.read(1, "u", init_simtime_u)

    message_count += 1
    total_bytes += sys.getsizeof(u)

    ym[0] = u[0] + 10
    print(f"pmpymax: u={u[0]:.2f} -> ym={ym[0]:.2f}")

    concore.write(1, "ym", ym, delta=1)   # delta=1 advances simtime → drives the loop

# --- Finalize and Report ---
end_time = time.monotonic()
duration = end_time - start_time
cpu_usage = process.cpu_percent() / duration if duration > 0 else 0

print("\n" + "="*30)
print("--- PMPYMAX_TEST: FINAL RESULTS ---")
print(f"Total messages processed: {message_count}")
print(f"Total data processed:     {total_bytes / 1024:.4f} KB")
print(f"Total execution time:     {duration:.4f} seconds")
print(f"Approximate CPU usage:    {cpu_usage:.2f}%")
print(f"concore retry count:      {concore.retrycount}")
print("="*30)
