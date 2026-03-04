mkdir PZ
copy .\src\pmpymax.py .\PZ\pmpymax.py
copy .\src\concore.py .\PZ\concore.py
copy .\src\concore_base.py .\PZ\concore_base.py
copy .\src\pmpymax.iport .\PZ\concore.iport
copy .\src\pmpymax.oport .\PZ\concore.oport
mkdir CZ
copy .\src\cpymax.py .\CZ\cpymax.py
copy .\src\concore.py .\CZ\concore.py
copy .\src\concore_base.py .\CZ\concore_base.py
copy .\src\cpymax.iport .\CZ\concore.iport
copy .\src\cpymax.oport .\CZ\concore.oport
mkdir F1
copy .\src\funcall_zmq.py .\F1\funcall_zmq.py
copy .\src\concore.py .\F1\concore.py
copy .\src\concore_base.py .\F1\concore_base.py
copy .\src\funcall_zmq.iport .\F1\concore.iport
copy .\src\funcall_zmq.oport .\F1\concore.oport
copy  .\src\funcall_zmq.dir\*.* .\F1
mkdir F2
copy .\src\funbody_zmq.py .\F2\funbody_zmq.py
copy .\src\concore.py .\F2\concore.py
copy .\src\concore_base.py .\F2\concore_base.py
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
