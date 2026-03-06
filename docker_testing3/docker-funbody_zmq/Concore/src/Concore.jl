"""
    Concore  — Docker-aware frontend

This file is the Docker counterpart to `Concore.jl`. It is NOT loaded
automatically — `mkconcore.py` copies it in place of `Concore.jl` when
generating build scripts for Docker targets.

It declares the same `module Concore` and includes the same `concore_base.jl`,
so from Julia's perspective (and the user's perspective) nothing changes:
user scripts always write `using Concore`. The only difference is this
frontend's `__init__()` which applies Docker-specific settings:

  1. Absolute mount paths  →  `/in`  and  `/out`
     (Docker volumes are bound at known absolute paths, not relative ./in ./out)

  2. Container-friendly logging  →  `INFO - message` format
     (mirrors concoredocker.py's `logging.basicConfig(format='%(levelname)s - %(message)s')`)

  3. Linux signal handling  →  SIGTERM / SIGINT handled cleanly
     (`docker stop` sends SIGTERM; containers are always Linux)

Mirrors the role of `concoredocker.py` relative to `concore.py`.
"""
module Concore

# ---------------------------------------------------------------
# All shared imports, source files, and exports
# (identical between this frontend and Concore.jl)
# ---------------------------------------------------------------
include("concore_base.jl")

# ---------------------------------------------------------------
# Docker module initialisation
# Runs once when `using Concore` is called inside a container.
# Does NOT contain any local-run logic — that lives in Concore.jl.
# ---------------------------------------------------------------
function __init__()
    # Refresh the ZMQ context at runtime! If the library was precompiled,
    # the ZMQ.Context() created in state.jl points to a destroyed C memory address,
    # which causes `ZMQ: Bad address` whenever we try to bind/connect.
    state.zmq_ctx = ZMQ.Context()

    # ------------------------------------------------------------------
    # 1. Absolute Docker volume mount paths
    #    Mirrors concoredocker.py:
    #        inpath  = os.path.abspath("/in")
    #        outpath = os.path.abspath("/out")
    #
    #    Docker containers have an isolated filesystem. The framework
    #    bind-mounts host directories at /in and /out — relative paths
    #    like ./in would point nowhere inside the container.
    # ------------------------------------------------------------------
    state.inpath  = "/in"
    state.outpath = "/out"

    # ------------------------------------------------------------------
    # 2. Container-friendly logging
    #    Mirrors concoredocker.py:
    #        logging.basicConfig(format='%(levelname)s - %(message)s')
    #
    #    `docker logs` is the only visibility into a container's output,
    #    so INFO-level logging is enabled by default and the format is
    #    kept minimal: "INFO - message".
    # ------------------------------------------------------------------
    function _docker_meta_formatter(level, _module, group, id, file, line)
        color  = Logging.default_logcolor(level)
        prefix = level == Logging.Warn ? "WARNING" : uppercase(string(level))
        return color, "$prefix -", ""
    end
    global_logger(ConsoleLogger(stderr, Logging.Info;
                                meta_formatter = _docker_meta_formatter))

    @info "Concore Docker mode: inpath=/in, outpath=/out"

    # ------------------------------------------------------------------
    # 3. Linux signal handling
    #    `docker stop` sends SIGTERM. Disabling exit-on-sigint ensures
    #    atexit hooks (terminate_zmq) run cleanly on both SIGTERM and
    #    Ctrl+C (SIGINT). Containers are always Linux — no Windows guard
    #    is needed and no concorekill.bat is written.
    # ------------------------------------------------------------------
    Base.exit_on_sigint(false)

    # ------------------------------------------------------------------
    # Standard initialisation (same order as Concore.jl)
    # Runs AFTER paths are set so load_params! reads from /in1/
    # ------------------------------------------------------------------
    load_params!()          # populate state.params from /in1/concore.params
    load_ports!()           # populate state.iport / state.oport
    default_maxtime(100.0)  # read maxtime from /in1/concore.maxtime (default 100 s)
    _init_shm_from_ports!() # set up SHM segments if numeric port keys are present
end

end # module Concore
