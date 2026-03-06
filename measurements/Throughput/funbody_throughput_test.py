# funbody_throughput.py
import time
import concore

print("Starting ZMQ throughput server (funbody)")

# --- ZMQ Configuration ---
# Ensure these environment variables are set before running
# Example: PORT_NAME_F2_OUT="F1_out" PORT_F2_OUT="5555" python funbody_throughput.py

# Initialize the ZMQ server port
concore.init_zmq_port(
    port_name=PORT_NAME_B_OUT,
    port_type="bind",
    address="tcp://0.0.0.0:" + PORT_B_OUT, # Bind to all interfaces on the specified port
    socket_type_str="REP"
)

# --- Server Loop ---
print(f"Funbody server listening on port {PORT_B_OUT}. Press Ctrl+C to stop.")

try:
    while True:
        # Wait to receive any message from a client
        received_message = concore.read(PORT_NAME_B_OUT, "throughput_test", "{}")

        if received_message:
            # As soon as a message is received, send a reply back
            reply_message = {"status": "ok"}
            concore.write(PORT_NAME_B_OUT, "throughput_reply", reply_message)
        else:
            # The read timed out; just continue waiting for the next message
            continue

except KeyboardInterrupt:
    print("\nServer shutting down.")

finally:
    # Clean up the ZMQ connection
    concore.terminate_zmq()