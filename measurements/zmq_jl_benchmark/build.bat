mkdir F1
copy .\src\A.jl .\F1\A.jl
xcopy /S /I /Y .\src\Concore .\F1\Concore
julia --project=.\F1\Concore -e "using Pkg; Pkg.instantiate()"
copy .\src\A.iport .\F1\concore.iport
copy .\src\A.oport .\F1\concore.oport
mkdir F2
copy .\src\B.jl .\F2\B.jl
xcopy /S /I /Y .\src\Concore .\F2\Concore
julia --project=.\F2\Concore -e "using Pkg; Pkg.instantiate()"
copy .\src\B.iport .\F2\concore.iport
copy .\src\B.oport .\F2\concore.oport
mkdir F3
copy .\src\C.jl .\F3\C.jl
xcopy /S /I /Y .\src\Concore .\F3\Concore
julia --project=.\F3\Concore -e "using Pkg; Pkg.instantiate()"
copy .\src\C.iport .\F3\concore.iport
copy .\src\C.oport .\F3\concore.oport
cd F1
cd ..
cd F2
cd ..
cd F3
cd ..
