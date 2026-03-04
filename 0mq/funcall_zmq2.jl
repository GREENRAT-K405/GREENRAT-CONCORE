# funcall_zmq2.jl
# Julia port of funcall_zmq2.py
# Same as funcall_zmq.jl but uses PORT_NAME_IN_F1 / PORT_IN_F1 instead of F2_F1.
# PORT_NAME_IN_F1 and PORT_IN_F1 are injected by mkconcore at deployment time.
import Concore: init_zmq_port, initval, concore_read, concore_write, unchanged, terminate_zmq, state

println("funcall using ZMQ via concore")

init_zmq_port(PORT_NAME_IN_F1, "connect", "tcp://localhost:" * PORT_IN_F1, "REQ")

state.delay   = 0.07
state.simtime = 0.0
state.maxtime = 100.0

init_simtime_u_str  = "[0.0, 0.0, 0.0]"
init_simtime_ym_str = "[0.0, 0.0, 0.0]"

u  = initval(init_simtime_u_str)
ym = initval(init_simtime_ym_str)

println("Initial u: $u, ym: $ym, concore.simtime: $(state.simtime)")
println("Max time: $(state.maxtime)")

while state.simtime < state.maxtime
    while unchanged()
        global u = concore_read(state.iport["U"], "u", init_simtime_u_str)
    end

    # concore_write prepends state.simtime automatically
    concore_write(PORT_NAME_IN_F1, "u_signal", u)

    # concore_read strips simtime prefix and updates state.simtime
    received_ym = concore_read(PORT_NAME_IN_F1, "ym_signal", init_simtime_ym_str)

    if received_ym isa AbstractVector && length(received_ym) > 0
        global ym = received_ym
    else
        println("Warning: Received unexpected ZMQ data format: $received_ym. Using default ym.")
        global ym = initval(init_simtime_ym_str)
    end

    if haskey(state.oport, "Y")
        concore_write(state.oport["Y"], "ym", ym)
    end

    println("funcall ZMQ u=$u ym=$ym time=$(state.simtime)")
end

println("funcall retry=" * string(state.retrycount))
terminate_zmq()
