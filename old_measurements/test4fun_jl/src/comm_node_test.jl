import Pkg; Pkg.activate("..")
using concore
using Dates

# --- Script Configuration ---
concore.delay_value[] = 0.07
concore.simtime_value[] = 0.0
# default_maxtime(100) ignored by new logic in python, so omitting here.
init_simtime_u = "[0.0, 0.0, 0.0]"
init_simtime_ym = "[0.0, 0.0, 0.0]"

# --- Measurement Initialization ---
messages_processed = 0
start_time = time()

# --- Main Script Logic ---
u = concore.initval(init_simtime_u)
ym = concore.initval(init_simtime_ym)
curr = 0.0
max_value = 10000.0
iteration = 0
iteration_limit = 1000 # Safety break

println("comm_node_test.jl started...")

while curr < max_value && iteration < iteration_limit
    global curr, iteration, u, ym, messages_processed
    
    # Wait for a message from the 'U' channel
    while concore.unchanged()
        u = concore.read_port(concore.iport["U"], "u", init_simtime_u)
    end
    
    # Forward it to the 'U1' channel
    concore.write_port(concore.oport["U1"], "u", u)
    curr = u[1]
    
    if curr >= max_value
        concore.write_port(concore.oport["Y"], "ym", [curr])
        break
    end

    # Wait for a message from the 'Y1' channel
    old2 = Float64(concore.simtime_value[])
    while concore.unchanged() || concore.simtime_value[] <= old2
        ym = concore.read_port(concore.iport["Y1"], "ym", init_simtime_ym)
    end
        
    # Forward it to the 'Y' channel
    concore.write_port(concore.oport["Y"], "ym", ym)
    curr = ym[1]
    
    println("comm_node: u=$(round(u[1], digits=2)) | ym=$(round(ym[1], digits=2))")
    
    messages_processed += 2
    iteration += 1
end

# --- Finalize and Report Measurements ---
end_time = time()
duration = end_time - start_time

println("\n" * "="^30)
println("--- COMM_NODE_TEST: FINAL RESULTS ---")
println("Total messages routed: $messages_processed")
println("Total execution time:  $(round(duration, digits=4)) seconds")
println("concore retry count:   $(concore.retry_count[])")
println("="^30)
