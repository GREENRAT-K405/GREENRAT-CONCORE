import Pkg; Pkg.activate("..")
using concore
using Dates

# --- Measurement & Script Configuration ---
concore.delay_value[] = 0.01 
init_simtime_u = "[0.0, 0.0, 0.0]"
init_simtime_ym = "[0.0, 0.0, 0.0]"

# --- Measurement Initialization ---
min_latency = Inf
max_latency = 0.0
total_latency = 0.0
message_count = 0
total_bytes = 0
overall_start_time = time()
wallclock1 = time_ns()

# --- Main Script Logic ---
u = concore.initval(init_simtime_u)
curr = 0.0
max_value = 10000.0
iteration_limit = 1000 # Safety break
iteration = 0

println("cpymax_test.jl started...")

# Initiate the loop by writing an initial value
println("ym=N/A u=$(round(u[1], digits=2)) (initial)")
concore.write_port("1", "u", u)

while curr < max_value && iteration < iteration_limit
    global curr, iteration, wallclock1
    global min_latency, max_latency, total_latency, message_count, total_bytes
    
    # Wait for the processed value to come back
    ym = Float64[]
    while concore.unchanged()
        ym = concore.read_port("1", "ym", init_simtime_ym)
    end
    
    wallclock2 = time_ns()
    latency_ms = (wallclock2 - wallclock1) / 1e6 # Round-trip time in milliseconds

    # Update metrics
    message_count += 1
    total_bytes += Base.summarysize(ym)
    min_latency = min(min_latency, latency_ms)
    max_latency = max(max_latency, latency_ms)
    total_latency += latency_ms

    # Prepare next value
    u[1] = ym[1]
    curr = u[1]
    println("ym=$(round(ym[1], digits=2)) u=$(round(u[1], digits=2)) | Latency: $(round(latency_ms, digits=2)) ms")
    
    # Write the value back into the loop
    concore.write_port("1", "u", u)
    wallclock1 = time_ns() # Reset timer for next round-trip
    iteration += 1
end

# --- Finalize and Report Measurements ---
overall_end_time = time()
total_duration = overall_end_time - overall_start_time
avg_latency = message_count > 0 ? total_latency / message_count : 0.0

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
# CPU usage not natively measured in Julia stdlib without shelling out.
println("concore retry count:      $(concore.retry_count[])")
println("="^30)
