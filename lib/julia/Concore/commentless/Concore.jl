module Concore

include("concore_base.jl")

function __init__()
    state.zmq_ctx = ZMQ.Context()

    if Sys.iswindows()
        open("concorekill.bat", "w") do f
            write(f, "taskkill /F /PID $(getpid())\n")
        end
    end

    load_params!()
    load_ports!()
    default_maxtime(100.0)
    _init_shm_from_ports!()
end

end
