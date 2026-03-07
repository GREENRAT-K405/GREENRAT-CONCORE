start /B /D "PZ" cmd /c "julia --project=Concore pmpymax_test.jl > concoreout.txt 2>&1"
start /B /D "CZ" cmd /c "julia --project=Concore cpymax_test.jl > concoreout.txt 2>&1"
start /B /D "F1" cmd /c "julia --project=Concore comm_node_test.jl > concoreout.txt 2>&1"
