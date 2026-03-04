# funbody_zmq2.jl
# Julia port of funbody_zmq2.py
# Same as funbody_zmq.jl but uses PORT_NAME_F2_OUT / PORT_F2_OUT instead of F2_F1.
# PORT_NAME_F2_OUT and PORT_F2_OUT are injected by mkconcore at deployment time.
import Concore: init_zmq_port, initval, concore_read, concore_write, unchanged, terminate_zmq, state

println("funbody using ZMQ via concore")

init_zmq_port(PORT_NAME_F2_OUT, "bind", "tcp://0.0.0.0:" * PORT_F2_OUT, "REP")

state.delay   = 0.07
state.simtime = 0.0
state.maxtime = 100.0

init_simtime_u_str  = "[0.0, 0.0, 0.0]"
init_simtime_ym_str = "[0.0, 0.0, 0.0]"

u_data_values  = initval(init_simtime_u_str)
ym_data_values = initval(init_simtime_ym_str)

println("Initial u_data_values: $u_data_values, ym_data_values: $ym_data_values")
println("Max time: $(state.maxtime)")

while state.simtime < state.maxtime
    global u_data_values = concore_read(PORT_NAME_F2_OUT, "u_signal", init_simtime_u_str)

    if !(u_data_values isa AbstractVector && length(u_data_values) > 0)
        println("Error or invalid data received via ZMQ: $u_data_values. Skipping iteration.")
        sleep(state.delay)
        continue
    end

    if haskey(state.oport, "U2")
        concore_write(state.oport["U2"], "u", u_data_values)
    end

    old_simtime = Float64(state.simtime)
    while unchanged() || state.simtime <= old_simtime
        global ym_data_values = concore_read(state.iport["Y2"], "ym", init_simtime_ym_str)
    end

    # concore_write prepends state.simtime automatically — do NOT manually prepend
    concore_write(PORT_NAME_F2_OUT, "ym_signal", ym_data_values)

    println("funbody u=$u_data_values ym=$ym_data_values time=$(state.simtime)")
end

println("funbody retry=" * string(state.retrycount))
terminate_zmq()
