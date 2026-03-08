"""
    Concore — Docker-aware frontend

Swapped in by mkconcore.py in place of Concore.jl when building Docker containers.
The user's script never changes — `using Concore` always works.

Differences from Concore.jl (all in __init__):
  1. Absolute paths /in and /out (Docker volumes bind at known absolute paths)
  2. Container-friendly logging — INFO level, plain format, to stderr
  3. SIGTERM handling for clean shutdown on `docker stop`
"""
module Concore

include("concore_base.jl")

function __init__()
    # Refresh ZMQ context — precompiled context pointers are stale at runtime.
    state.zmq_ctx = ZMQ.Context()

    # 1. Docker volumes are mounted at absolute paths /in and /out.
    state.inpath  = "/in"
    state.outpath = "/out"

    # 2. Format log output as "INFO - message" so `docker logs` is readable.
    function _docker_meta_formatter(level, _module, group, id, file, line)
        color  = Logging.default_logcolor(level)
        prefix = level == Logging.Warn ? "WARNING" : uppercase(string(level))
        return color, "$prefix -", ""
    end
    global_logger(ConsoleLogger(stderr, Logging.Info;
                                meta_formatter = _docker_meta_formatter))

    @info "Concore Docker mode: inpath=/in, outpath=/out"

    # 3. Ensure atexit hooks (terminate_zmq) run on both SIGTERM and Ctrl+C.
    Base.exit_on_sigint(false)

    load_params!()
    load_ports!()
    default_maxtime(100.0)
    _init_shm_from_ports!()
end

end # module Concore
