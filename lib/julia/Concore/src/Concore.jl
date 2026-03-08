"""
    Concore — local (POSIX / Windows) frontend

Three transport backends are supported:
- File Method (FM): shared filesystem, works everywhere
- Shared Memory (SM): POSIX System V SHM via `ccall`, Linux only
- ZeroMQ: socket-based transport for distributed nodes

Quick example:
    using Concore
    x = concore_read(1, "x", "[0, 0.0]")
    concore_write(1, "y", [1.0, 2.0])
    if !unchanged() ... end

Note on Docker: mkconcore.py swaps this file for concoredocker.jl when
building containers. User scripts always just write `using Concore`.
"""
module Concore

include("concore_base.jl")

function __init__()
    # Refresh ZMQ context — precompiled context pointers are stale at runtime.
    state.zmq_ctx = ZMQ.Context()

    # Write a kill-script on Windows so the stop script can kill by PID.
    if Sys.iswindows()
        try
            open("concorekill.bat", "w") do f
                write(f, "taskkill /F /PID $(getpid())\n")
            end
        catch e
            @warn "Could not write concorekill.bat: $e"
        end
    end

    load_params!()
    load_ports!()
    default_maxtime(100.0)
    _init_shm_from_ports!()
end

end # module Concore
