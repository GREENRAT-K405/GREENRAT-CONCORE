# cpymax_test.jl
# Julia port of cpymax_test.py
# Controller node: reads ym from port 1, sets u[1] = ym[1]+1, writes u back.
# Measures per-iteration round-trip latency and overall execution stats.
import Concore: initval, concore_read, concore_write, unchanged, state, default_maxtime

function main()
    # --- Script Configuration ---
    # maxtime controls number of iterations (each pmpymax write increments simtime by 1)
    state.delay = 0.01
    default_maxtime(1000.0)   # 1000 round trips

    init_simtime_u  = "[0.0, 0.0, 0.0]"
    init_simtime_ym = "[0.0, 0.0, 0.0]"

    # --- Measurement Initialization ---
    min_latency   = typemax(Float64)
    max_latency   = 0.0
    total_latency = 0.0
    message_count = 0
    total_bytes   = 0
    overall_start_time = time()
    wallclock1         = time_ns()

    # --- Main Script Logic ---
    u = initval(init_simtime_u)

    println("cpymax_test.jl started...")

    # Wait for first ym to arrive (pmpymax starts the chain with delta=1)
    ym = concore_read(1, "ym", init_simtime_ym)
    while state.simtime < state.maxtime
        while unchanged()
            ym = concore_read(1, "ym", init_simtime_ym)
        end

        wallclock2 = time_ns()
        latency_ms = (wallclock2 - wallclock1) / 1.0e6   # nanoseconds → milliseconds

        # Update metrics
        message_count += 1
        total_bytes   += Base.summarysize(ym)
        min_latency    = min(min_latency, latency_ms)
        max_latency    = max(max_latency, latency_ms)
        total_latency += latency_ms

        # Prepare and send next value
        u[1] = ym[1] + 1.0
        println("ym=$(round(ym[1], digits=2)) u=$(round(u[1], digits=2)) | Latency: $(round(latency_ms, digits=2)) ms")

        concore_write(1, "u", u)
        wallclock1 = time_ns()
    end

    # --- Finalize and Report Measurements ---
    overall_end_time = time()
    total_duration   = overall_end_time - overall_start_time
    avg_latency      = message_count > 0 ? total_latency / message_count : 0.0

    println("\n" * "="^30)
    println("--- CPYMAX_TEST: FINAL RESULTS ---")
    println("Total loop iterations:    $message_count")
    println("Total data received:      $(round(total_bytes / 1024, digits=4)) KB")
    println("Total execution time:     $(round(total_duration, digits=4)) seconds")
    println("-" ^ 30)
    println("Min round-trip latency:   $(round(min_latency, digits=2)) ms")
    println("Avg round-trip latency:   $(round(avg_latency, digits=2)) ms")
    println("Max round-trip latency:   $(round(max_latency, digits=2)) ms")
    println("-" ^ 30)
    # CPU usage requires shelling out in Julia; omitted (no psutil equivalent in stdlib)
    println("concore retry count:      $(state.retrycount)")
    println("="^30)
end

main()
