# secondNode.jl
# Julia port of secondNode.py (Node B — Server)
# Binds a REP socket, waits for Node A to send a value, adds 0.01, sends it back.
# PORT_F1_F2 and PORT_NAME_F1_F2 are injected by mkconcore at deployment time.
import Concore: init_zmq_port, concore_read, concore_write, terminate_zmq, state

init_zmq_port(
    "0x$(PORT_F1_F2)_$(PORT_NAME_F1_F2)",
    "bind",
    "tcp://0.0.0.0:" * PORT_F1_F2,
    "REP"
)

println("Node B server started. Waiting for requests...")

port_b = "0x$(PORT_F1_F2)_$(PORT_NAME_F1_F2)"

while true
    received_data  = concore_read(port_b, "value", [0.0])
    received_value = received_data isa AbstractVector ? received_data[1] : Float64(received_data)

    println("Node B: Received $(round(received_value, digits=2)) from Node A.")

    new_value = received_value + 0.01
    println("Node B: Sending back processed value $(round(new_value, digits=2)).")

    concore_write(port_b, "value", [new_value])

    if new_value > 100.0
        break
    end
end

println("\nNode B: Terminating.")
terminate_zmq()
