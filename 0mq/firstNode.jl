# firstNode.jl
# Julia port of firstNode.py (Node A — Orchestrator/Client)
# Opens two REQ sockets: one to Node B (secondNode), one to Node C (thirdNode).
# Sends a value to B, gets reply, sends that result to C, uses C's reply as the next value.
# PORT_F1_F2, PORT_NAME_F1_F2, PORT_F1_F3, PORT_NAME_F1_F3 are injected by mkconcore.
import Concore: init_zmq_port, concore_read, concore_write, terminate_zmq, state

# Connect to Node B
init_zmq_port(
    "0x$(PORT_F1_F2)_$(PORT_NAME_F1_F2)",
    "connect",
    "tcp://localhost:" * PORT_F1_F2,
    "REQ"
)

# Connect to Node C
init_zmq_port(
    "0x$(PORT_F1_F3)_$(PORT_NAME_F1_F3)",
    "connect",
    "tcp://localhost:" * PORT_F1_F3,
    "REQ"
)

current_value = 0.0

while current_value <= 100.0
    port_b = "0x$(PORT_F1_F2)_$(PORT_NAME_F1_F2)"
    port_c = "0x$(PORT_F1_F3)_$(PORT_NAME_F1_F3)"

    # --- Step 1: Communicate with Node B ---
    println("Node A: Sending value $(round(current_value, digits=2)) to Node B.")
    concore_write(port_b, "value", [current_value])

    value_from_b = concore_read(port_b, "value", [current_value])
    processed_by_b = value_from_b isa AbstractVector ? value_from_b[1] : value_from_b
    println("Node A: Received processed value $(round(processed_by_b, digits=2)) from Node B.")

    # --- Step 2: Communicate with Node C ---
    println("Node A: Sending value $(round(processed_by_b, digits=2)) to Node C.")
    concore_write(port_c, "value", [processed_by_b])

    value_from_c = concore_read(port_c, "value", [processed_by_b])
    global current_value = value_from_c isa AbstractVector ? value_from_c[1] : value_from_c
    println("Node A: Received final value $(round(current_value, digits=2)) from Node C.")
    println("-" ^ 20)

    sleep(1)  # Slow down for readability
end

println("\nNode A: Value exceeded 100. Terminating.")
terminate_zmq()
