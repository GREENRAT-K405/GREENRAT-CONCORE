    using ZMQ
    using JSON
    using Logging

    export concore_read, concore_write,
        unchanged, initval,
        init_zmq_port, terminate_zmq,
        default_maxtime, tryparam,
        iport, oport

    include("state.jl")
    include("params.jl")
    include("ports.jl")
    include("zmq.jl")
    include("shm.jl")
    include("io.jl")
