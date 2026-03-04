# funcall2_zmq.py
import time 
import concore

print("funcall using ZMQ via concore")

# Standalone ZMQ ports for testing
PORT_NAME_F2_F1 = "F2_F1"
PORT_F2_F1 = "5556"

# Initialize ZMQ REQ port using concore
concore.init_zmq_port(
    port_name = PORT_NAME_F2_F1,
    port_type="connect",
    address="tcp://localhost:" + PORT_F2_F1,
    socket_type_str="REQ" 
)

# Standard concore initializations
concore.delay = 0.07        
concore.simtime = 0
concore.default_maxtime(100) 
init_simtime_u_str = "[0.0, 0.0, 0.0]"
init_simtime_ym_str = "[0.0, 0.0, 0.0]"

u = concore.initval(init_simtime_u_str)
ym = concore.initval(init_simtime_ym_str) 

print(f"Initial u: {u}, ym: {ym}, concore.simtime: {concore.simtime}, concore.simtime: {concore.simtime}")
concore.maxtime = 100
print(f"Max time overridden to: {concore.maxtime}")

while concore.simtime < concore.maxtime:
    # In a full system, this would wait for file updates via concore.unchanged()
    # For standalone ZMQ testing, we'll just simulate a time step and generate some 'u' data.
    time.sleep(1) 
    concore.simtime += 1
    u = [float(concore.simtime), 2.0, 3.0] # Mock data

    data_to_send_u = [concore.simtime] + u
    
    concore.write(PORT_NAME_F2_F1, "u_signal", data_to_send_u)

    received_ym_result = concore.read(PORT_NAME_F2_F1, "ym_signal", init_simtime_ym_str)
    if isinstance(received_ym_result, tuple):
        received_ym_data = received_ym_result[0]
    else:
        received_ym_data = received_ym_result

    if isinstance(received_ym_data, list) and len(received_ym_data) > 0:
        response_time = received_ym_data[0]
        if isinstance(response_time, (int, float)):
            concore.simtime = response_time 
            ym = received_ym_data[1:]      
        else:
            print(f"Warning: Received ZMQ data's first element is not time: {received_ym_data}. Using as is.")
            ym = received_ym_data 
    else:
        print(f"Warning: Received unexpected ZMQ data format: {received_ym_data}. Using default ym.")
        ym = concore.initval(init_simtime_ym_str) 

    # Assuming concore.oport['Y'] is a file port (e.g., to cpymax.py)
    # concore.write(concore.oport['Y'], "ym", ym)
    pass
    
    print(f"funcall ZMQ u={u} ym={ym} time={concore.simtime}")

print("funcall retry=" + str(concore.retrycount))

concore.terminate_zmq()