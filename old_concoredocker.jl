"""
    concoredocker

A thin Docker-aware adaptation of Concore that swaps relative paths for absolute
container mount points, adjusts logging, and handles container-specific termination.
"""
module concoredocker

using Logging
using Concore

function __init__()
    # ------------------------------------------------------------------------
    # 1. Container-friendly logging
    # Mirrors concoredocker.py: "%(levelname)s - %(message)s" format
    # ------------------------------------------------------------------------
    function docker_meta_formatter(level, _module, group, id, file, line)
        color = Logging.default_logcolor(level)
        prefix = level == Logging.Warn ? "WARNING" : uppercase(string(level))
        return color, "$prefix -", ""
    end
    
    global_logger(ConsoleLogger(stderr, Logging.Info; meta_formatter=docker_meta_formatter))

    # ------------------------------------------------------------------------
    # 2. Swap relative paths for absolute container mount points
    # Mirrors concoredocker.py: inpath = "/in", outpath = "/out"
    # ------------------------------------------------------------------------
    Concore.state.inpath = "/in"
    Concore.state.outpath = "/out"

    # Since the paths changed, reload params and maxtime from the new absolute paths
    Concore.load_params!()
    Concore.default_maxtime(100.0)

    # ------------------------------------------------------------------------
    # 3. Handle Linux Signals
    # Docker uses SIGTERM to stop and SIGINT for Ctrl+C. 
    # Concore already sets up `ccall(:signal, ...)` for SIGTERM and 
    # `Base.exit_on_sigint(false)` for SIGINT, ensuring `atexit(terminate_zmq)`
    # runs. We enforce this here explicitly.
    # ------------------------------------------------------------------------
    if Sys.islinux()
        Base.exit_on_sigint(false)
    end
end

# Re-export the standard Concore public API
import Concore: concore_read, concore_write, unchanged, initval, 
                init_zmq_port, terminate_zmq, default_maxtime, tryparam, 
                iport, oport

export concore_read, concore_write, unchanged, initval, 
       init_zmq_port, terminate_zmq, default_maxtime, tryparam, 
       iport, oport

end # module concoredocker
