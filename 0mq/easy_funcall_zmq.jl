# easy_funcall_zmq.jl
import Concore: init_zmq_port, initval, concore_read, concore_write, terminate_zmq
import Concore: state

println("funcall using ZMQ via concore")

# Standalone ZMQ ports for testing
PORT_NAME_F2_F1 = "F2_F1"
PORT_F2_F1 = "5556"

# Initialize ZMQ REQ port using concore
init_zmq_port(
    PORT_NAME_F2_F1,
    "connect",
    "tcp://127.0.0.1:" * PORT_F2_F1, 
    "REQ" 
)

# Standard concore initializations
state.delay = 0.07        
state.simtime = 0.0
state.maxtime = 100.0

init_simtime_u_str = "[0.0, 0.0, 0.0]"
init_simtime_ym_str = "[0.0, 0.0, 0.0]"

u_data_values = initval(init_simtime_u_str)
ym_data_values = initval(init_simtime_ym_str) 

println("Initial u: $u_data_values, ym: $ym_data_values, concore.simtime: $(state.simtime), concore.simtime: $(state.simtime)")
println("Max time overridden to: $(state.maxtime)")

while state.simtime < state.maxtime
    # In a full system, this would wait for file updates via concore.unchanged()
    # For standalone ZMQ testing, we'll just simulate a time step and generate some 'u' data.
    sleep(1.0) 
    state.simtime += 1.0
    global u_data_values = [Float64(state.simtime), 2.0, 3.0] # Mock data

    # Concore.jl's concore_write for ZMQ automatically prepends state.simtime 
    # if the value is a vector, so we don't need to manually prepend it like Python does.
    concore_write(PORT_NAME_F2_F1, "u_signal", u_data_values)

    # Concore.jl's concore_read for ZMQ automatically strips the simtime 
    # and updates state.simtime if it's a vector with simtime as the first element.
    received_ym_result = concore_read(PORT_NAME_F2_F1, "ym_signal", init_simtime_ym_str)
    
    if received_ym_result isa AbstractVector
        global ym_data_values = received_ym_result
    else
        println("Warning: Received unexpected ZMQ data format: $received_ym_result. Using default ym.")
        global ym_data_values = initval(init_simtime_ym_str)
    end

    # Assuming concore.oport['Y'] is a file port (e.g., to cpymax.py)
    if haskey(state.oport, "Y")
        concore_write(state.oport["Y"], "ym", ym_data_values)
    end
    
    println("funcall ZMQ u=$(u_data_values) ym=$(ym_data_values) time=$(state.simtime)")
end

println("funcall retry=" * string(state.retrycount))

terminate_zmq()
