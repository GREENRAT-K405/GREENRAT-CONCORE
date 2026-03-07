# A.jl (Client and Primary Measurement Node)
# Julia port of A.py
# Sends values through the B→C pipeline and measures round-trip latency.
import Concore: init_zmq_port, concore_read, concore_write, terminate_zmq, state

# --- Fallback port definitions (normally injected by copy_with_port_portname.py) ---
if !@isdefined(PORT_NAME_F1_F2)
    const PORT_NAME_F1_F2 = "F1_F2"
    println("Warning: Port variables not injected. Running in standalone mode with default values.")
    println("         For full study behavior, run via study generation (makestudy).")
end
if !@isdefined(PORT_F1_F2)
    const PORT_F1_F2 = "5555"
end

function main()
    # --- ZMQ Initialization ---
    # REQ socket connects to Node B (which binds and waits)
    init_zmq_port(PORT_NAME_F1_F2, "connect", "tcp://localhost:" * PORT_F1_F2, "REQ")

    println("Node A client started.")

    # --- Measurement Initialization ---
    min_latency   = typemax(Float64)
    max_latency   = 0.0
    total_latency = 0.0
    message_count = 0
    total_bytes   = 0
    overall_start_time = time()

    current_value = 0.0
    max_value     = 10000.0

    # Warmup loop: do 5 passes to let the JIT compiler optimize before timing
    for _ in 1:5
        concore_write(PORT_NAME_F1_F2, "value", [current_value])
        concore_read(PORT_NAME_F1_F2, "value", [0.0])
    end

    while current_value < max_value
        loop_start_time = time_ns()   # start high-res timer for round-trip latency
        # println("Node A: Sending value $(round(current_value, digits=2)) to Node B.")

        # 1. Send the current value as a request into the pipeline
        concore_write(PORT_NAME_F1_F2, "value", [current_value])
        total_bytes += sizeof(Float64)

        # 2. Wait for the final processed value in reply
        received_data = concore_read(PORT_NAME_F1_F2, "value", [0.0])

        loop_end_time = time_ns()
        latency_ms    = (loop_end_time - loop_start_time) / 1.0e6

        # Update metrics
        message_count += 1
        min_latency    = min(min_latency, latency_ms)
        max_latency    = max(max_latency, latency_ms)
        total_latency += latency_ms

        current_value = received_data[1]   # Julia is 1-indexed
        println("Node A: Received final value $(round(current_value, digits=2)) from the pipeline. | Latency: $(round(latency_ms, digits=2)) ms")
        # println("-" ^ 20)
    end

    # --- Finalize and Report Measurements ---
    overall_end_time = time()
    total_duration   = overall_end_time - overall_start_time
    avg_latency      = message_count > 0 ? total_latency / message_count : 0.0

    println("\n" * "="^35)
    println("--- NODE A: END-TO-END RESULTS ---")
    println("Total pipeline iterations: $message_count")
    println("Total data sent:           $(round(total_bytes / 1024, digits=4)) KB")
    println("Total End-to-End Time:     $(round(total_duration, digits=4)) seconds")
    println("-" ^ 35)
    println("Min round-trip latency:    $(round(min_latency, digits=2)) ms")
    println("Avg round-trip latency:    $(round(avg_latency, digits=2)) ms")
    println("Max round-trip latency:    $(round(max_latency, digits=2)) ms")
    println("-" ^ 35)
    # CPU usage requires shelling out in Julia; omitted (no psutil equivalent in stdlib)
    println("="^35)

    println("\nNode A: Final value $(round(current_value, digits=2)) reached the target. Terminating.")
    terminate_zmq()
end

main()
