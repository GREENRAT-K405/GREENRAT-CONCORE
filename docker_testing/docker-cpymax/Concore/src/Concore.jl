"""
    Concore

Julia implementation of the Concore communication library.

Concore provides lightweight inter-component communication for simulation
frameworks via three transport backends:

- **File Method (FM)**: shared filesystem paths, works everywhere
- **Shared Memory (SM)**: POSIX System V SHM via `ccall`, Linux only
- **ZeroMQ**: socket-based transport for distributed/networked components

# Quickstart

```julia
using Concore

# Read a value from port 1, variable "x", defaulting to [0.0]
x = concore_read(1, "x", "[0, 0.0]")

# Write a value to port 1, variable "y"
concore_write(1, "y", [1.0, 2.0])

# Check if inputs have changed since last iteration
if !unchanged()
    # process new data ...
end
```

See the individual function docstrings for full API documentation.

# Note on Docker
When building for Docker, mkconcore.py copies `concoredocker.jl` in place of
this file. That frontend declares the same `module Concore` but with a
Docker-aware `__init__()` (absolute mount paths /in /out, container logging,
Linux signal handling). User scripts are never modified.
"""
module Concore

# ---------------------------------------------------------------
# All shared imports, source files, and exports
# (identical between this frontend and concoredocker.jl)
# ---------------------------------------------------------------
include("concore_base.jl")

# ---------------------------------------------------------------
# Local (POSIX / Windows) module initialisation
# Runs once when `using Concore` is called on a local machine.
# Does NOT contain any Docker logic — that lives in concoredocker.jl.
# ---------------------------------------------------------------
function __init__()
    # Refresh the ZMQ context at runtime! If the library was precompiled,
    # the ZMQ.Context() created in state.jl points to a destroyed C memory address,
    # which causes `ZMQ: Bad address` whenever we try to bind/connect.
    state.zmq_ctx = ZMQ.Context()

    # On Windows, write a helper batch file so the stop script
    # can kill this process by PID (mirrors concore.py behaviour).
    if Sys.iswindows()
        try
            open("concorekill.bat", "w") do f
                write(f, "taskkill /F /PID $(getpid())\n")
            end
        catch e
            @warn "Could not write concorekill.bat: $e"
        end
    end

    load_params!()          # populate state.params from concore.params file
    load_ports!()           # populate state.iport / state.oport
    default_maxtime(100.0)  # read maxtime from file (default 100 s)
    _init_shm_from_ports!() # set up SHM segments if numeric port keys are present
end

end # module Concore
