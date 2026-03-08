# funcall_throughput_test.jl
import Concore

println("Starting ZMQ throughput test (funcall) in Julia")

# --- ZMQ Configuration ---
# mkconcore.py injects the real values if used with docker, 
# but for raw benchmarking we define defaults:
PORT_NAME_IN_A = "throughput_port"
PORT_IN_A = "5555"

# Initialize the ZMQ connection to the funbody server
Concore.init_zmq_port(PORT_NAME_IN_A, "connect", "tcp://127.0.0.1:" * PORT_IN_A, "REQ")

# --- Test Parameters ---
TEST_DURATION_SECONDS = 10.0
message_to_send = Dict("ping" => "hello")
message_count = 0

println("Running test for ", TEST_DURATION_SECONDS, " seconds...")

start_time = time()
end_time = start_time + TEST_DURATION_SECONDS

# --- Main Test Loop ---
while time() < end_time
    Concore.concore_write(PORT_NAME_IN_A, "throughput_test", message_to_send)
    
    reply = Concore.concore_read(PORT_NAME_IN_A, "throughput_reply", "{}")

    # concore_read parses JSON into a Dict. It's empty only on timeout/error.
    if !isempty(reply)
        global message_count += 1
    else
        println("Warning: Missed a reply from the server.")
        break
    end
end

# --- Calculate and Print Results ---
actual_duration = time() - start_time
throughput = message_count / actual_duration

println("\n--- Throughput Test Complete ---")
println("Total messages exchanged: ", message_count)
println("Total time: ", round(actual_duration, digits=2), " seconds")
println("Throughput: ", round(throughput, digits=2), " messages/sec")
println("---------------------------------")

# Clean up the ZMQ connection
Concore.terminate_zmq()
