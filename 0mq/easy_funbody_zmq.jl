# easy_funbody_zmq.jl
import Concore: init_zmq_port, initval, concore_read, concore_write, terminate_zmq
import Concore: state

println("funbody using ZMQ via concore")

# Standalone ZMQ ports for testing
PORT_NAME_F2_F1 = "F2_F1"
PORT_F2_F1 = "5556"

# Initialize ZMQ REP port using concore
init_zmq_port(
    PORT_NAME_F2_F1,
    "bind",
    "tcp://127.0.0.1:" * PORT_F2_F1,
    "REP" 
)

# Standard concore initializations
state.delay = 0.07         
state.simtime = 0.0      
state.maxtime = 100.0

init_simtime_u_str = "[0.0, 0.0, 0.0]"
init_simtime_ym_str = "[0.0, 0.0, 0.0]"

u_data_values = initval(init_simtime_u_str) 
ym_data_values = initval(init_simtime_ym_str)

println("Initial u_data_values: $u_data_values, ym_data_values: $ym_data_values")
println("Max time overridden to: $(state.maxtime)")

while state.simtime < state.maxtime
    received_u_result = concore_read(PORT_NAME_F2_F1, "u_signal", init_simtime_u_str)

    received_u_data = received_u_result
    ok = true

    if !(received_u_data isa AbstractVector && length(received_u_data) > 0)
        println("Error or invalid data received via ZMQ: $received_u_data. Skipping iteration.")
        sleep(state.delay) 
        continue 
    end

    # Note: concore_read already strips the time prefix and updates state.simtime
    # This differs from Python's read() returning [simtime, ...values] for ZMQ.
    # So received_u_data is ALREADY just the values, not [time, values]!
    # Update simtime from state.
    
    global u_data_values = received_u_data

    # Assuming concore.oport['U2'] is a file port (e.g., to pmpymax.py)
    if haskey(state.oport, "U2") 
        concore_write(state.oport["U2"], "u", u_data_values)
    end
    
    # In a full system, this would wait for file updates from pmpymax
    # For standalone ZMQ testing, we'll mock the 'ym' calculation
    # Only map using float to assure typing is correct
    global ym_data_values = [Float64(v) * 2.0 for v in u_data_values]

    # concore_write prepends state.simtime automatically — do NOT manually
    # vcat([state.simtime], ...) here or funcall will see a double simtime prefix.
    concore_write(PORT_NAME_F2_F1, "ym_signal", ym_data_values)
    
    println("funbody u=$u_data_values ym=$ym_data_values time=$(state.simtime)")
end

println("funbody retry=" * string(state.retrycount))

terminate_zmq()
