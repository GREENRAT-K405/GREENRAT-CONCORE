mkdir PZ
copy .\src\pmpymax.jl .\PZ\pmpymax.jl
xcopy /S /I /Y .\src\Concore .\PZ\Concore
julia --project=.\PZ\Concore -e "using Pkg; Pkg.instantiate()"
copy .\src\pmpymax.iport .\PZ\concore.iport
copy .\src\pmpymax.oport .\PZ\concore.oport
mkdir CZ
copy .\src\cpymax.jl .\CZ\cpymax.jl
xcopy /S /I /Y .\src\Concore .\CZ\Concore
julia --project=.\CZ\Concore -e "using Pkg; Pkg.instantiate()"
copy .\src\cpymax.iport .\CZ\concore.iport
copy .\src\cpymax.oport .\CZ\concore.oport
mkdir F1
copy .\src\funcall_zmq.jl .\F1\funcall_zmq.jl
xcopy /S /I /Y .\src\Concore .\F1\Concore
julia --project=.\F1\Concore -e "using Pkg; Pkg.instantiate()"
copy .\src\funcall_zmq.iport .\F1\concore.iport
copy .\src\funcall_zmq.oport .\F1\concore.oport
copy  .\src\funcall_zmq.dir\*.* .\F1
mkdir F2
copy .\src\funbody_zmq.jl .\F2\funbody_zmq.jl
xcopy /S /I /Y .\src\Concore .\F2\Concore
julia --project=.\F2\Concore -e "using Pkg; Pkg.instantiate()"
copy .\src\funbody_zmq.iport .\F2\concore.iport
copy .\src\funbody_zmq.oport .\F2\concore.oport
copy  .\src\funbody_zmq.dir\*.* .\F2
mkdir U
mkdir Y
mkdir U2
mkdir Y2
cd CZ
mklink /J out1 ..\U
cd ..
cd F1
mklink /J out1 ..\Y
cd ..
cd F2
mklink /J out1 ..\U2
cd ..
cd PZ
mklink /J out1 ..\Y2
cd ..
cd PZ
mklink /J in1 ..\U2
cd ..
cd CZ
mklink /J in1 ..\Y
cd ..
cd F1
mklink /J in1 ..\U
cd ..
cd F2
mklink /J in1 ..\Y2
cd ..
