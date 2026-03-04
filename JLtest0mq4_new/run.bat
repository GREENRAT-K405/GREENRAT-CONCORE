start /B /D "PZ" julia --project=Concore "pmpymax.jl" >"PZ"\concoreout.txt
start /B /D "CZ" julia --project=Concore "cpymax.jl" >"CZ"\concoreout.txt
start /B /D "F1" julia --project=Concore "funcall_zmq.jl" >"F1"\concoreout.txt
start /B /D "F2" julia --project=Concore "funbody_zmq.jl" >"F2"\concoreout.txt
