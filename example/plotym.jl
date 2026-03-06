import Concore: initval, concore_read, concore_write, unchanged, state, default_maxtime
using Plots

println("plotym - Live Mode")

# Simulation Configuration
state.delay = 0.02
default_maxtime(150.0)
const init_simtime_ym = "[0.0, 0.0]"

global ym = initval(init_simtime_ym)

# Initialize Live Plot
plt = plot(Float64[], Float64[], title="Live plots", xlabel="Cycles", ylabel="ym", legend=:topright, label="ym", lw=2)

x_data = Int[]
ym1_data = Float64[]

try
    while state.simtime < state.maxtime
        while unchanged()
            global ym = concore_read(1, "ym", init_simtime_ym)
        end
        
        concore_write(1, "ym", ym, 0.0)
        println("ym=$ym")
        
        push!(x_data, length(x_data))
        push!(ym1_data, ym[1])
        
        # Update plot line data by pushing newest point
        push!(plt, 1, x_data[end], ym1_data[end])
        
        sleep(0.001)
    end
catch e
    if isa(e, InterruptException)
        println("\nSimulation interrupted by user.")
    else
        rethrow(e)
    end
end

println("retry=$(state.retrycount)")

# Finalize plot
savefig(plt, "ym_live_final.pdf")
