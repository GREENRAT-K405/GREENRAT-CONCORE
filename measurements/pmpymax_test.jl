# pmpymax_test.jl
# Julia port of pmpymax_test.py
# Plant-model node: reads u from port 1, computes ym[1] = u[1] + 10, writes ym back.
# Drives simtime forward with delta=1 on each write.
import Concore: initval, concore_read, concore_write, unchanged, state, default_maxtime

function main()
    # --- Script Configuration ---
    state.delay = 0.01
    default_maxtime(1000.0)   # must match cpymax's maxtime

    init_simtime_u  = "[0.0, 0.0, 0.0]"
    init_simtime_ym = "[0.0, 0.0, 0.0]"

    # --- Measurement Initialization ---
    start_time    = time()
    message_count = 0
    total_bytes   = 0

    # --- Main Script Logic ---
    ym = initval(init_simtime_ym)

    println("pmpymax_test.jl started...")

    u = concore_read(1, "u", init_simtime_u)
    # pmpymax drives the pipeline: on each tick it reads u, increments, and writes ym
    # (advancing simtime with delta=1)
    while state.simtime < state.maxtime
        while unchanged()
            u = concore_read(1, "u", init_simtime_u)
        end

        message_count += 1
        total_bytes   += Base.summarysize(u)

        ym[1] = u[1] + 10.0
        println("pmpymax: u=$(round(u[1], digits=2)) -> ym=$(round(ym[1], digits=2))")

        concore_write(1, "ym", ym, 1)   # delta=1 advances simtime → drives the loop
    end

    # --- Finalize and Report ---
    end_time = time()
    duration = end_time - start_time

    println("\n" * "="^30)
    println("--- PMPYMAX_TEST: FINAL RESULTS ---")
    println("Total messages processed: $message_count")
    println("Total data processed:     $(round(total_bytes / 1024, digits=4)) KB")
    println("Total execution time:     $(round(duration, digits=4)) seconds")
    # CPU usage requires shelling out in Julia; omitted (no psutil equivalent in stdlib)
    println("concore retry count:      $(state.retrycount)")
    println("="^30)
end

main()
