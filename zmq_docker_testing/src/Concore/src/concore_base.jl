# Shared base included into both Concore.jl (local) and concoredocker.jl (Docker).
# Not a module itself — just imports, includes, and exports that are identical in both frontends.

using ZMQ
using JSON
using Logging

export concore_read, concore_write,
       unchanged, initval,
       init_zmq_port, terminate_zmq,
       default_maxtime, tryparam,
       iport, oport

# Source files must be included in this order — later files depend on earlier ones.
include("state.jl")   # global state structs
include("params.jl")  # safe parsing + parameter loading
include("ports.jl")   # iport / oport loading
include("zmq.jl")     # ZeroMQ transport
include("shm.jl")     # Shared Memory (Linux only)
include("io.jl")      # public API: concore_read / concore_write
