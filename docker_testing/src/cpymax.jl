# cpymax.jl
# Julia port of cpymax.py
# Controller node: reads ym from file port 1, sets u[1] = ym[1]+1, writes u back.
# Also tracks min/avg/max wall-clock elapsed time per iteration.
import Concore: initval, concore_read, concore_write, unchanged, state

state.delay = 0.01

init_simtime_u  = "[0.0, 0.0, 0.0]"
init_simtime_ym = "[0.0, 0.0, 0.0]"

min_elapsed = typemax(Float64)
max_elapsed = typemin(Float64)
sum_elapsed = 0.0

u         = initval(init_simtime_u)
wallclock1 = time()

while state.simtime < state.maxtime
    while unchanged()
        global ym = concore_read(1, "ym", init_simtime_ym)
    end
    global u
    u[1] = ym[1] + 1.0
    println("ym=$(ym[1]) u=$(u[1])")
    concore_write(1, "u", u)

    wallclock2 = time()
    elapsed    = wallclock2 - wallclock1
    global sum_elapsed += elapsed
    global wallclock1   = wallclock2
    global min_elapsed  = min(min_elapsed, elapsed)
    global max_elapsed  = max(max_elapsed, elapsed)
end

println("retry=" * string(state.retrycount))
println("min=$min_elapsed")
println("avg=$(sum_elapsed / state.maxtime)")
println("max=$max_elapsed")
