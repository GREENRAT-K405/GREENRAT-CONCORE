start /D "PZ" cmd /K julia --project=Concore "pmpymax_test.jl"
start /D "CZ" cmd /K julia --project=Concore "cpymax_test.jl"
start /D "F1" cmd /K julia --project=Concore "comm_node_test.jl"
