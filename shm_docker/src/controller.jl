import Concore: initval, concore_read, concore_write, unchanged, state, default_maxtime

const ysp = 3.0

function controller(ym)
    if ym[1] < ysp
        return 1.01 .* ym
    else
        return 0.9 .* ym
    end
end

default_maxtime(150.0)
state.delay = 0.02

const init_simtime_u = "[0.0, 0.0]"
const init_simtime_ym = "[0.0, 0.0]"

global u = initval(init_simtime_u)
global ym = nothing

while state.simtime < state.maxtime
    while unchanged()
        global ym = concore_read(1, "ym", init_simtime_ym)
    end
    
    #####
    global u = controller(ym)
    #####
    
    println("$(state.simtime). u=$u ym=$ym")
    
    concore_write(1, "u", u, 0)
end

println("retry=$(state.retrycount)")
