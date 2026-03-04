# funbody.jl / funbody2.jl
# Julia port of funbody.py and funbody2.py
#
# NOTE: The Python originals use `osparc_control.PairedTransmitter` for RPC
# (ports 2345/2346). There is no Julia equivalent of osparc_control in this
# codebase, so this translation replaces PairedTransmitter with a plain ZMQ
# REP socket — the same REQ/REP pattern used by funbody_zmq.jl.
# The core concore logic (file-port relay to U2 / read from Y2) is preserved.
#
# To match the Python behaviour exactly you would need to implement or bind to
# the osparc-control protocol in Julia, which is out of scope here.
import Concore: init_zmq_port, initval, concore_read, concore_write, unchanged, terminate_zmq, state

println("funbody 0mq")

# Use a fixed local port that mirrors the Python PairedTransmitter listen_port=2345
const LISTEN_PORT = "2345"
const PORT_NAME   = "funbody_rpc"

init_zmq_port(PORT_NAME, "bind", "tcp://0.0.0.0:" * LISTEN_PORT, "REP")

state.delay   = 0.07
state.simtime = 0.0

init_simtime_u_str  = "[0.0, 0.0, 0.0]"
init_simtime_ym_str = "[0.0, 0.0, 0.0]"

u_data_values  = initval(init_simtime_u_str)
ym_data_values = initval(init_simtime_ym_str)

while state.simtime < state.maxtime
    # Receive the RPC "fun" request — contains [simtime, u1, u2, ...]
    # concore_read strips simtime prefix and updates state.simtime automatically
    global u_data_values = concore_read(PORT_NAME, "u", init_simtime_u_str)

    if !(u_data_values isa AbstractVector && length(u_data_values) > 0)
        println("No valid command received, waiting...")
        sleep(0.01)
        continue
    end

    println(u_data_values)

    if haskey(state.oport, "U2")
        concore_write(state.oport["U2"], "u", u_data_values)
    end

    old_simtime = Float64(state.simtime)
    while unchanged() || state.simtime <= old_simtime
        global ym_data_values = concore_read(state.iport["Y2"], "ym", init_simtime_ym_str)
    end

    println("Replying with $ym_data_values")
    # concore_write prepends state.simtime automatically — the reply is [simtime, ym...]
    concore_write(PORT_NAME, "ym", ym_data_values)

    println("funbody u=$u_data_values ym=$ym_data_values time=$(state.simtime)")
end

println("retry=" * string(state.retrycount))
terminate_zmq()
