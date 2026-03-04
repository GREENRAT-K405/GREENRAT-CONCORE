# firstNode.py (Client/Orchestrator)
import concore
import time

# --- ZMQ Initialization ---
# This REQ socket connects to Node B (F2)
concore.init_zmq_port(
    port_name=f"0x{PORT_F1_F2}_{PORT_NAME_F1_F2}",
    port_type="connect",
    address="tcp://localhost:" + PORT_F1_F2,
    socket_type_str="REQ"
)
# This REQ socket connects to Node C (F3)
concore.init_zmq_port(
    port_name=f"0x{PORT_F1_F3}_{PORT_NAME_F1_F3}",
    port_type="connect",
    address="tcp://localhost:" + PORT_F1_F3,
    socket_type_str="REQ"
)

current_value = 0.0

while current_value <= 100:
    # --- Step 1: Communicate with Node B ---
    print(f"Node A: Sending value {current_value:.2f} to Node B.")
    concore.write(f"0x{PORT_F1_F2}_{PORT_NAME_F1_F2}", "value", [current_value])

    # Wait for the reply from Node B
    value_from_b = concore.read(f"0x{PORT_F1_F2}_{PORT_NAME_F1_F2}", "value", [current_value])
    processed_by_b = value_from_b[0]
    print(f"Node A: Received processed value {processed_by_b:.2f} from Node B.")

    # --- Step 2: Communicate with Node C ---
    print(f"Node A: Sending value {processed_by_b:.2f} to Node C.")
    concore.write(f"0x{PORT_F1_F3}_{PORT_NAME_F1_F3}", "value", [processed_by_b])

    # Wait for the reply from Node C
    value_from_c = concore.read(f"0x{PORT_F1_F3}_{PORT_NAME_F1_F3}", "value", [processed_by_b])
    current_value = value_from_c[0]
    print(f"Node A: Received final value {current_value:.2f} from Node C.")
    print("-" * 20)
    time.sleep(1) # Slow down the loop for readability

print("\nNode A: Value exceeded 100. Terminating.")
concore.terminate_zmq()