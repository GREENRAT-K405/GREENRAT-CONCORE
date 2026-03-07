import concore
import time
import os
import psutil
import sys

# --- Script Configuration ---
concore.delay = 0.01
init_simtime_u = "[0.0, 0.0, 0.0]"
init_simtime_ym = "[0.0, 0.0, 0.0]"

# --- Measurement Initialization ---
process = psutil.Process(os.getpid())
start_time = time.monotonic()
message_count = 0
total_bytes = 0

# --- Main Script Logic ---
ym = concore.initval(init_simtime_ym)
curr = 0.0
max_value = 100.0
iteration = 0
iteration_limit = 15 # Safety break

print("pmpymax_test.py started...")

while curr < max_value and iteration < iteration_limit:
    # Wait for a value from the other node
    while concore.unchanged():
        u = concore.read(1, "u", init_simtime_u)
    
    # Update metrics for received data
    message_count += 1
    total_bytes += sys.getsizeof(u)

    # Process the value
    ym[0] = u[0] + 10 # Using a smaller increment to match the A-B-C logic
    curr = ym[0]
    print(f"pmpymax: u={u[0]:.2f} -> ym={ym[0]:.2f}")
    
    # Write the processed value back
    concore.write(1, "ym", ym, delta=1)
    iteration += 1

# --- Finalize and Report Measurements ---
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
