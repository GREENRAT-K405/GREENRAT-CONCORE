start /B /D "PZ" julia --project=Concore "pmpymax_test.jl" >"PZ"\concoreout.txt
start /B /D "CZ" julia --project=Concore "cpymax_test.jl" >"CZ"\concoreout.txt
start /B /D "F1" julia --project=Concore "comm_node_test.jl" >"F1"\concoreout.txt
