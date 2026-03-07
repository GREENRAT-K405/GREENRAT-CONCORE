import Pkg; Pkg.activate("..")
using concore
using Dates

# --- Script Configuration ---
concore.delay_value[] = 0.01
init_simtime_u = "[0.0, 0.0, 0.0]"
init_simtime_ym = "[0.0, 0.0, 0.0]"

# --- Measurement Initialization ---
start_time = time()
message_count = 0
total_bytes = 0

# --- Main Script Logic ---
ym = concore.initval(init_simtime_ym)
curr = 0.0
max_value = 10000.0
iteration = 0
iteration_limit = 1000 # Safety break

println("pmpymax_test.jl started...")

while curr < max_value && iteration < iteration_limit
    global curr, iteration, ym, total_bytes, message_count
    
    # Wait for a value from the other node
    u = Float64[]
    while concore.unchanged()
        u = concore.read_port("1", "u", init_simtime_u)
    end
    
    # Update metrics for received data
    message_count += 1
    total_bytes += Base.summarysize(u)

    # Process the value
    ym[1] = u[1] + 10 # Using a smaller increment to match the A-B-C logic
    curr = ym[1]
    println("pmpymax: u=$(round(u[1], digits=2)) -> ym=$(round(ym[1], digits=2))")
    
    # Write the processed value back
    concore.write_port("1", "ym", ym, delta=1.0)
    iteration += 1
end

# --- Finalize and Report Measurements ---
end_time = time()
duration = end_time - start_time

println("\n" * "="^30)
println("--- PMPYMAX_TEST: FINAL RESULTS ---")
println("Total messages processed: $message_count")
println("Total data processed:     $(round(total_bytes / 1024, digits=4)) KB")
println("Total execution time:     $(round(duration, digits=4)) seconds")
println("concore retry count:      $(concore.retry_count[])")
println("="^30)
