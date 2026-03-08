# funbody_throughput_test.jl
import Concore

println("Starting ZMQ throughput server (funbody) in Julia")

# --- ZMQ Configuration ---
PORT_NAME_B_OUT = "throughput_port"
PORT_B_OUT = "5555"

# Initialize the ZMQ server port
Concore.init_zmq_port(PORT_NAME_B_OUT, "bind", "tcp://*:" * PORT_B_OUT, "REP")

# --- Server Loop ---
println("Funbody server listening on port ", PORT_B_OUT, ". Press Ctrl+C to stop.")

try
    while true
        # Wait to receive any message from a client
        received_message = Concore.concore_read(PORT_NAME_B_OUT, "throughput_test", "{}")

        if !isempty(received_message) && received_message != "{}"
            # As soon as a message is received, send a reply back
            reply_message = Dict("status" => "ok")
            Concore.concore_write(PORT_NAME_B_OUT, "throughput_reply", reply_message)
        end
    end
catch e
    if isa(e, InterruptException)
        println("\nServer shutting down.")
    else
        rethrow(e)
    end
finally
    # Clean up the ZMQ connection
    Concore.terminate_zmq()
end
