# C.jl (Processing Server and Measurement Endpoint)
# Julia port of C.py
# Receives values from B, increments by 10, sends reply back.
import Concore: init_zmq_port, concore_read, concore_write, terminate_zmq, state

# --- Fallback port definitions (normally injected by copy_with_port_portname.py) ---
if !@isdefined(PORT_NAME_F2_F3)
    const PORT_NAME_F2_F3 = "F2_F3"
    println("Warning: Port variables not injected. Running in standalone mode with default values.")
    println("         For full study behavior, run via study generation (makestudy).")
end
if !@isdefined(PORT_F2_F3)
    const PORT_F2_F3 = "5556"
end

function main()
    # --- ZMQ Initialization ---
    # REP socket: binds and waits for requests from Node B
    init_zmq_port(PORT_NAME_F2_F3, "bind", "tcp://*:" * PORT_F2_F3, "REP")

    println("Node C server started. Waiting for requests...")

    # --- Measurement Initialization ---
    start_time    = time()
    message_count = 0
    total_bytes   = 0

    while true
        # 1. Wait to receive a request from Node B
        received_data  = concore_read(PORT_NAME_F2_F3, "value", [0.0])
        received_value = received_data[1]   # Julia is 1-indexed

        # Track received data for metrics
        message_count += 1
        total_bytes   += sizeof(Float64) * length(received_data)

        println("Node C: Received $(round(received_value, digits=2)) from Node B.")

        # 2. Process the value (increment by 10)
        new_value = received_value + 10.0
        println("Node C: Sending back processed value $(round(new_value, digits=2)).")

        # 3. Send the reply back to Node B
        concore_write(PORT_NAME_F2_F3, "value", [new_value])

        # 4. Check the value to know when to shut down gracefully
        if new_value >= 10000.0
            break
        end
    end

    # --- Finalize and Report Measurements ---
    end_time = time()
    duration = end_time - start_time

    println("\n" * "="^30)
    println("--- NODE C: RESULTS ---")
    println("Total messages processed: $message_count")
    println("Total data processed:     $(round(total_bytes / 1024, digits=4)) KB")
    println("Total execution time:     $(round(duration, digits=4)) seconds")
    # CPU usage requires shelling out in Julia; omitted (no psutil equivalent in stdlib)
    println("="^30)

    println("\nNode C: Terminating.")
    terminate_zmq()
end

main()
