# comm_node.jl
# Julia port of comm_node.py
# Relay node: reads U from iport, writes U1 to oport, reads Y1 from iport, writes Y to oport.
import Concore: initval, concore_read, concore_write, unchanged, state

println("comm_node")

state.delay   = 0.07
state.simtime = 0.0
state.maxtime = 100.0

init_simtime_u  = "[0.0, 0.0, 0.0]"
init_simtime_ym = "[0.0, 0.0, 0.0]"

u  = initval(init_simtime_u)
ym = initval(init_simtime_ym)

while state.simtime < state.maxtime
    while unchanged()
        global u = concore_read(state.iport["U"], "u", init_simtime_u)
    end
    concore_write(state.oport["U1"], "u", u)
    println(u)

    old2 = Float64(state.simtime)
    while unchanged() || state.simtime <= old2
        global ym = concore_read(state.iport["Y1"], "ym", init_simtime_ym)
    end
    concore_write(state.oport["Y"], "ym", ym)
    println("comm_node u=$u ym=$ym time=$(state.simtime)")
end

println("retry=" * string(state.retrycount))
