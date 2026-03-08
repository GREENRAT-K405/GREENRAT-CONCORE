start /D "CZ" cmd /K python "controller.py"
start /D "PZ" cmd /K julia --project=Concore "pm.jl"
start /D "XZ" cmd /K python "plotym.py"
