# secondNode.py (Server B)
import concore

# --- ZMQ Initialization ---
# This REP socket binds and waits for Node A to connect and send a request.
concore.init_zmq_port(
    port_name=f"0x{PORT_F1_F2}_{PORT_NAME_F1_F2}",
    port_type="bind",
    address="tcp://*:" + PORT_F1_F2,
    socket_type_str="REP"
)

print("Node B server started. Waiting for requests...")

while True:
    # Wait to receive a request from Node A
    received_data = concore.read(f"0x{PORT_F1_F2}_{PORT_NAME_F1_F2}", "value", [0.0])
    received_value = received_data[0]

    print(f"Node B: Received {received_value:.2f} from Node A.")

    # Process the value
    new_value = received_value + 0.01
    print(f"Node B: Sending back processed value {new_value:.2f}.")

    # Send the reply back to Node A
    concore.write(f"0x{PORT_F1_F2}_{PORT_NAME_F1_F2}", "value", [new_value])

    if new_value > 100:
        break

print("\nNode B: Terminating.")
concore.terminate_zmq()