# pmpymax.jl
# Julia port of pmpymax.py
# Plant model node: reads u from file port 1, computes ym[1] = u[1] + 10000, writes ym back.
import Concore: initval, concore_read, concore_write, unchanged, state

state.delay   = 0.01
state.maxtime = 100.0   # mirrors Python: concore.default_maxtime(100)

init_simtime_u  = "[0.0, 0.0, 0.0]"
init_simtime_ym = "[0.0, 0.0, 0.0]"

ym = initval(init_simtime_ym)

while state.simtime < state.maxtime
    while unchanged()
        global u = concore_read(1, "u", init_simtime_u)
    end
    global ym
    ym[1] = u[1] + 10000.0
    println("ym=$(ym[1]) u=$(u[1])")
    concore_write(1, "ym", ym, 1)   # delta=1 matches Python: concore.write(1,"ym",ym,delta=1)
end

println("retry=" * string(state.retrycount))
