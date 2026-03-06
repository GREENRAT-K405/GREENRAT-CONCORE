# =============================================================================
# concore_base.jl — Shared base for both Concore frontends
#
# This file is NOT a module. It is included inside both:
#   - Concore.jl        (local POSIX/Windows frontend)
#   - concoredocker.jl  (Docker frontend, swapped in by mkconcore.py)
#
# It contains everything that is identical between the two frontends:
#   - Package imports (using)
#   - Source file includes (state, params, ports, zmq, shm, io)
#   - Public API exports
#
# Each frontend provides only its own environment-specific __init__().
# =============================================================================

using ZMQ
using JSON
using Logging

# ---------------------------------------------------------------
# Public API exports  (identical in both frontends)
# ---------------------------------------------------------------
export concore_read, concore_write,
       unchanged, initval,
       init_zmq_port, terminate_zmq,
       default_maxtime, tryparam,
       iport, oport

# ---------------------------------------------------------------
# Source files (order matters: later files depend on earlier ones)
# ---------------------------------------------------------------
include("state.jl")   # Structs + global state instances (ConcoreState, ZeroMQPort, ShmState)
include("params.jl")  # safe_parse, parse_params, load_params!, tryparam, default_maxtime
include("ports.jl")   # load_ports!, iport(), oport()
include("zmq.jl")     # init_zmq_port, terminate_zmq, send/recv helpers, signal handling
include("shm.jl")     # Shared memory (Linux only): create/get/cleanup + read_SM/write_SM
include("io.jl")      # concore_read, concore_write, unchanged, initval
