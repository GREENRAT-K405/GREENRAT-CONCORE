mkdir CZ
copy .\src\controller.py .\CZ\controller.py
copy .\src\concore.py .\CZ\concore.py
copy .\src\controller.iport .\CZ\concore.iport
copy .\src\controller.oport .\CZ\concore.oport
mkdir PZ
copy .\src\pm.py .\PZ\pm.py
copy .\src\concore.py .\PZ\concore.py
copy .\src\pm.iport .\PZ\concore.iport
copy .\src\pm.oport .\PZ\concore.oport
mkdir XZ
copy .\src\plotym.py .\XZ\plotym.py
copy .\src\concore.py .\XZ\concore.py
copy .\src\plotym.iport .\XZ\concore.iport
copy .\src\plotym.oport .\XZ\concore.oport
mkdir CU
mkdir PYM
mkdir XYM
cd CZ
mklink /J out1 ..\CU
cd ..
cd PZ
mklink /J out1 ..\PYM
cd ..
cd XZ
mklink /J out1 ..\XYM
cd ..
cd CZ
mklink /J in1 ..\XYM
cd ..
cd PZ
mklink /J in1 ..\CU
cd ..
cd XZ
mklink /J in1 ..\PYM
cd ..
