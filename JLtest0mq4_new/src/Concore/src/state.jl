# ===================================================================
# State Structs & Global Instances
# ===================================================================

"""
    ZeroMQPort

Holds a ZMQ socket together with its connection metadata.
"""
mutable struct ZeroMQPort
    socket::ZMQ.Socket
    port_type::String
    address::String
    ctx::ZMQ.Context   # owning context (may be shared or per-socket on Windows)
end

# ===================================================================
# Shared Memory State (Linux only — mirrors concore.hpp)
# ===================================================================
#
# concore.hpp uses POSIX System V SHM (shmget / shmat / shmdt / shmctl).
# We replicate the same logic via ccall so the Julia process can talk to
# C++ counterparts sharing the same SHM key.
#
# Communication mode: 0 = File Method (FM), 1 = Shared Memory (SM)

"""
    ShmState

Mirrors the SHM fields of the C++ `Concore` class.
Only meaningful on Linux; fields are initialised to sentinel values
(id = -1, ptr = NULL, mode = 0) everywhere else.
"""
mutable struct ShmState
    # IDs returned by shmget (-1 = not initialised)
    shmId_create::Int32        # used by the *writer* (oport)
    shmId_get::Int32           # used by the *reader* (iport)

    # Pointers returned by shmat (Ptr{Cchar}(0) = not attached)
    sharedData_create::Ptr{Cchar}
    sharedData_get::Ptr{Cchar}

    # Mode flags (0 = FM, 1 = SM)
    communication_oport::Int
    communication_iport::Int
end

const SHM_STATE = ShmState(Int32(-1), Int32(-1), Ptr{Cchar}(0), Ptr{Cchar}(0), 0, 0)

# System V SHM constants (Linux ABI)
const IPC_CREAT  = 0o1000
const IPC_RMID   = 0
const SHM_SIZE   = 256        # matches C++: shmget(key, 256, ...)

"""
    ConcoreState

Module-level mutable state, mirroring all the global variables used in
`concore.py` and the member fields of the C++ `Concore` class.
"""
mutable struct ConcoreState
    inpath::String
    outpath::String
    simtime::Float64
    delay::Float64
    s::String
    olds::String
    retrycount::Int
    zmq_ports::Dict{String, ZeroMQPort}
    zmq_ctx::ZMQ.Context
    params::Dict{String, Any}
    cleanup_in_progress::Bool
    iport::Dict{String, Any}
    oport::Dict{String, Any}
    maxtime::Float64
end

# Global state instance (matches Python's module-level variables)
const state = ConcoreState(
    "./in", "./out", 0.0, 1.0, "", "", 0,
    Dict{String, ZeroMQPort}(), ZMQ.Context(),
    Dict{String, Any}(), false,
    Dict{String, Any}(), Dict{String, Any}(),
    100.0  # mirrors Python's default_maxtime(100)
)

# Write concorekill.bat on Windows so batch run scripts can terminate this process by PID
# Mirrors Python: if hasattr(sys, 'getwindowsversion'): open("concorekill.bat","w").write(...)
if Sys.iswindows()
    try
        open("concorekill.bat", "w") do f
            write(f, "taskkill /F /PID $(getpid())\n")
        end
    catch e
        @warn "Could not write concorekill.bat: $e"
    end
end
