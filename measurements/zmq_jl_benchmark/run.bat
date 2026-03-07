start /B /D "F1" cmd /c "julia --project=Concore A.jl > concoreout.txt 2>&1"
start /B /D "F2" cmd /c "julia --project=Concore B.jl > concoreout.txt 2>&1"
start /B /D "F3" cmd /c "julia --project=Concore C.jl > concoreout.txt 2>&1"
