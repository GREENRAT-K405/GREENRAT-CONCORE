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
"""
module Concore

using ZMQ
using JSON

# ---------------------------------------------------------------
# Public API exports
# ---------------------------------------------------------------
export concore_read, concore_write,
       unchanged, initval,
       init_zmq_port, terminate_zmq,
       default_maxtime, tryparam,
       iport, oport

# ---------------------------------------------------------------
# Source files (order matters: later files depend on earlier ones)
# ---------------------------------------------------------------
include("state.jl")    # Structs + global state instances
include("params.jl")   # safe_parse, parse_params, load_params!, tryparam, default_maxtime
include("ports.jl")    # load_ports!, iport(), oport()
include("zmq.jl")      # init_zmq_port, terminate_zmq, send/recv helpers, signal handling
include("shm.jl")      # Shared memory (Linux only): create/get/cleanup + read_SM/write_SM
include("io.jl")       # concore_read, concore_write, unchanged, initval

# ---------------------------------------------------------------
# Module initialisation (runs once when `using Concore` is called)
# ---------------------------------------------------------------
load_params!()          # populate state.params from concore.params file
load_ports!()           # populate state.iport / state.oport
_init_shm_from_ports!() # set up SHM segments if numeric port keys are present

end # module Concore
