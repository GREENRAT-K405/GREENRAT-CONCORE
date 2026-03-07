# comm_node_test.jl
# Julia port of comm_node_test.py
# Relay node: reads U from iport, forwards to U1; reads Y1 from iport, forwards to Y.
# Counts messages routed and reports final timing stats.
import Concore: initval, concore_read, concore_write, unchanged, state, default_maxtime

function main()
    # --- Script Configuration ---
    state.delay   = 0.07
    state.simtime = 0.0
    default_maxtime(1000.0)   # must match other nodes

    init_simtime_u  = "[0.0, 0.0, 0.0]"
    init_simtime_ym = "[0.0, 0.0, 0.0]"

    # --- Measurement Initialization ---
    messages_processed = 0
    start_time         = time()

    # --- Main Script Logic ---
    u  = initval(init_simtime_u)
    ym = initval(init_simtime_ym)

    println("comm_node_test.jl started...")

    while state.simtime < state.maxtime
        # 1. Wait for a message from the 'U' channel (from cpymax)
        while unchanged()
            u = concore_read(state.iport["U"], "u", init_simtime_u)
        end

        # 2. Forward it to the 'U1' channel (to pmpymax)
        concore_write(state.oport["U1"], "u", u)

        # 3. Wait for the reply from 'Y1' channel (from pmpymax), using simtime to avoid stale reads
        old2 = Float64(state.simtime)
        while unchanged() || state.simtime <= old2
            ym = concore_read(state.iport["Y1"], "ym", init_simtime_ym)
        end

        # 4. Forward the reply to 'Y' channel (to cpymax)
        concore_write(state.oport["Y"], "ym", ym)

        println("comm_node: u=$(round(u[1], digits=2)) | ym=$(round(ym[1], digits=2))")
        messages_processed += 1
    end

    # --- Finalize and Report ---
    end_time = time()
    duration = end_time - start_time

    println("\n" * "="^30)
    println("--- COMM_NODE_TEST: FINAL RESULTS ---")
    println("Total messages routed: $messages_processed")
    println("Total execution time:  $(round(duration, digits=4)) seconds")
    println("concore retry count:   $(state.retrycount)")
    println("="^30)
end

main()
