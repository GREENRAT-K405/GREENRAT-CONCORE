# funcall.jl / funcall2.jl
# Julia port of funcall.py and funcall2.py
#
# NOTE: The Python originals use `osparc_control.PairedTransmitter` on ports
# 2345/2346. There is no Julia equivalent of osparc_control in this codebase,
# so this translation replaces PairedTransmitter with a plain ZMQ REQ socket — 
# the same REQ/REP pattern used by funcall_zmq.jl.
# The transmitter connects to funbody.jl which listens on port 2345.
import Concore: init_zmq_port, initval, concore_read, concore_write, unchanged, terminate_zmq, state

println("funcall 0mq")

# Connect to funbody.jl which listens on the PairedTransmitter listen_port=2345
const REMOTE_PORT = "2345"
const PORT_NAME   = "funcall_rpc"

init_zmq_port(PORT_NAME, "connect", "tcp://localhost:" * REMOTE_PORT, "REQ")

state.delay   = 0.07
state.simtime = 0.0
state.maxtime = 100.0

init_simtime_u_str  = "[0.0, 0.0, 0.0]"
init_simtime_ym_str = "[0.0, 0.0, 0.0]"

u  = initval(init_simtime_u_str)
ym = initval(init_simtime_ym_str)

while state.simtime < state.maxtime
    # Wait until upstream file-port U has new data
    while unchanged()
        global u = concore_read(state.iport["U"], "u", init_simtime_u_str)
    end
    println(u)

    # Send RPC "fun" request: [simtime, u...] — concore_write prepends simtime automatically
    concore_write(PORT_NAME, "u", u)

    # Receive reply [simtime, ym...] — concore_read strips simtime and updates state.simtime
    received_ym = concore_read(PORT_NAME, "ym", init_simtime_ym_str)

    if received_ym isa AbstractVector && length(received_ym) > 0
        global ym = received_ym
    else
        println("Warning: Unexpected reply format: $received_ym. Using default ym.")
        global ym = initval(init_simtime_ym_str)
    end

    if haskey(state.oport, "Y")
        concore_write(state.oport["Y"], "ym", ym)
    end

    println("funcall 0mq u=$u ym=$ym time=$(state.simtime)")
end

println("retry=" * string(state.retrycount))
terminate_zmq()
