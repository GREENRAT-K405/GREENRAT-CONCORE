mutable struct ZeroMQPort
    socket::ZMQ.Socket
    port_type::String
    address::String
    ctx::ZMQ.Context
end

mutable struct ShmState
    shmId_create::Int32
    shmId_get::Int32
    sharedData_create::Ptr{Cchar}
    sharedData_get::Ptr{Cchar}
    communication_oport::Int
    communication_iport::Int
end

const SHM_STATE = ShmState(Int32(-1), Int32(-1), Ptr{Cchar}(0), Ptr{Cchar}(0), 0, 0)
const IPC_CREAT = 0o1000
const IPC_RMID  = 0
const SHM_SIZE  = 256

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

const state = ConcoreState(
    "./in", "./out", 0.0, 1.0, "", "", 0,
    Dict{String, ZeroMQPort}(), ZMQ.Context(),
    Dict{String, Any}(), false,
    Dict{String, Any}(), Dict{String, Any}(),
    100.0
)
