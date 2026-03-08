module Concore

include("concore_base.jl")

function __init__()
    state.zmq_ctx = ZMQ.Context()
    state.inpath  = "/in"
    state.outpath = "/out"

    function _fmt(level, _module, group, id, file, line)
        prefix = level == Logging.Warn ? "WARNING" : uppercase(string(level))
        return Logging.default_logcolor(level), "$prefix -", ""
    end
    global_logger(ConsoleLogger(stderr, Logging.Info; meta_formatter = _fmt))

    Base.exit_on_sigint(false)
    load_params!()
    load_ports!()
    default_maxtime(100.0)
    _init_shm_from_ports!()
end

end
