# funcall_throughput.py
import time
import concore

print("Starting ZMQ throughput test (funcall)")

# --- ZMQ Configuration ---
# Ensure these environment variables are set before running
# Example: PORT_NAME_IN_F1="F1_out" PORT_IN_F1="5555" python funcall_throughput.py

# Initialize the ZMQ connection to the funbody server
concore.init_zmq_port(
    port_name=PORT_NAME_IN_A,
    port_type="connect",
    address="tcp://192.168.0.109:" + PORT_IN_A, # Use 127.0.0.1 for local testing
    socket_type_str="REQ"
)

# --- Test Parameters ---
TEST_DURATION_SECONDS = 10
message_to_send = {"ping": "hello"}
message_count = 0

print(f"Running test for {TEST_DURATION_SECONDS} seconds...")

start_time = time.perf_counter()
end_time = start_time + TEST_DURATION_SECONDS

# --- Main Test Loop ---
while time.perf_counter() < end_time:
    # Send a message to the funbody server
    concore.write(PORT_NAME_IN_A, "throughput_test", message_to_send)
    
    # Wait for the reply
    reply = concore.read(PORT_NAME_IN_A, "throughput_reply", "{}")

    # If we get a valid reply, increment our counter
    if reply:
        message_count += 1
    else:
        print("Warning: Missed a reply from the server.")
        # In a real-world scenario, you might want to break or handle this
        break

# --- Calculate and Print Results ---
actual_duration = time.perf_counter() - start_time
throughput = message_count / actual_duration

print("\n--- Throughput Test Complete ---")
print(f"Total messages exchanged: {message_count}")
print(f"Total time: {actual_duration:.2f} seconds")
print(f"Throughput: {throughput:.2f} messages/sec")
print("---------------------------------")


# Clean up the ZMQ connection
concore.terminate_zmq()