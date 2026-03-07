mkdir PZ
copy .\src\pmpymax_test.py .\PZ\pmpymax_test.py
copy .\src\concore.py .\PZ\concore.py
copy .\src\pmpymax_test.iport .\PZ\concore.iport
copy .\src\pmpymax_test.oport .\PZ\concore.oport
mkdir CZ
copy .\src\cpymax_test.py .\CZ\cpymax_test.py
copy .\src\concore.py .\CZ\concore.py
copy .\src\cpymax_test.iport .\CZ\concore.iport
copy .\src\cpymax_test.oport .\CZ\concore.oport
mkdir F1
copy .\src\comm_node_test.py .\F1\comm_node_test.py
copy .\src\concore.py .\F1\concore.py
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
