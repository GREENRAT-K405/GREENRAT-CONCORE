mkdir PZ
copy .\src\pmpymax_test.jl .\PZ\pmpymax_test.jl
xcopy /S /I /Y .\src\Concore .\PZ\Concore
julia --project=.\PZ\Concore -e "using Pkg; Pkg.instantiate()"
copy .\src\pmpymax_test.iport .\PZ\concore.iport
copy .\src\pmpymax_test.oport .\PZ\concore.oport
mkdir CZ
copy .\src\cpymax_test.jl .\CZ\cpymax_test.jl
xcopy /S /I /Y .\src\Concore .\CZ\Concore
julia --project=.\CZ\Concore -e "using Pkg; Pkg.instantiate()"
copy .\src\cpymax_test.iport .\CZ\concore.iport
copy .\src\cpymax_test.oport .\CZ\concore.oport
mkdir F1
copy .\src\comm_node_test.jl .\F1\comm_node_test.jl
xcopy /S /I /Y .\src\Concore .\F1\Concore
julia --project=.\F1\Concore -e "using Pkg; Pkg.instantiate()"
copy .\src\comm_node_test.iport .\F1\concore.iport
copy .\src\comm_node_test.oport .\F1\concore.oport
copy  .\src\comm_node_test.dir\*.* .\F1
mkdir U
mkdir Y
mkdir U1
mkdir Y1
cd CZ
mklink /J out1 ..\U
cd ..
cd F1
mklink /J out1 ..\Y
cd ..
cd F1
mklink /J out2 ..\U1
cd ..
cd PZ
mklink /J out1 ..\Y1
cd ..
cd PZ
mklink /J in1 ..\U1
cd ..
cd CZ
mklink /J in1 ..\Y
cd ..
cd F1
mklink /J in1 ..\U
mklink /J in2 ..\Y1
cd ..
