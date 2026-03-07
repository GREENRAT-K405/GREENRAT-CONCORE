import concore
import time
import sys

# --- Script Configuration ---
concore.delay = 0.07
concore.simtime = 0
concore.default_maxtime(1000)   # must match other nodes
init_simtime_u  = "[0.0, 0.0, 0.0]"
init_simtime_ym = "[0.0, 0.0, 0.0]"

# --- Measurement Initialization ---
messages_processed = 0
start_time = time.monotonic()

# --- Main Script Logic ---
u  = concore.initval(init_simtime_u)
ym = concore.initval(init_simtime_ym)

print("comm_node_test.py started...")

while concore.simtime < concore.maxtime:
    # 1. Wait for a message from the 'U' channel (from cpymax)
    while concore.unchanged():
        u = concore.read(concore.iport['U'], "u", init_simtime_u)

    # 2. Forward it to the 'U1' channel (to pmpymax)
    concore.write(concore.oport['U1'], "u", u)

    # 3. Wait for the reply from 'Y1' channel (from pmpymax), using simtime to avoid stale reads
    old2 = float(concore.simtime)
    while concore.unchanged() or concore.simtime <= old2:
        ym = concore.read(concore.iport['Y1'], "ym", init_simtime_ym)

    # 4. Forward the reply to 'Y' channel (to cpymax)
    concore.write(concore.oport['Y'], "ym", ym)

    print(f"comm_node: u={u[0]:.2f} | ym={ym[0]:.2f}")
    messages_processed += 1

# --- Finalize and Report ---
end_time = time.monotonic()
duration = end_time - start_time

print("\n" + "="*30)
print("--- COMM_NODE_TEST: FINAL RESULTS ---")
print(f"Total messages routed: {messages_processed}")
print(f"Total execution time:  {duration:.4f} seconds")
print(f"concore retry count:   {concore.retrycount}")
print("="*30)
