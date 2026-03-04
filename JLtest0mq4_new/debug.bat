start /D "PZ" cmd /K julia --project=Concore "pmpymax.jl"
start /D "CZ" cmd /K julia --project=Concore "cpymax.jl"
start /D "F1" cmd /K julia --project=Concore "funcall_zmq.jl"
start /D "F2" cmd /K julia --project=Concore "funbody_zmq.jl"
