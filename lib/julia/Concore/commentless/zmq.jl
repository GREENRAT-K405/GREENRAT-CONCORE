function send_json_with_retry(port::ZeroMQPort, message)
    json_msg = JSON.json(message)
    for attempt in 1:5
        try ZMQ.send(port.socket, json_msg); return
        catch; sleep(0.5) end
    end
    @error "Failed to send after retries."
end

function recv_json_with_retry(port::ZeroMQPort)
    for attempt in 1:5
        try return JSON.parse(String(ZMQ.recv(port.socket)))
        catch; sleep(0.5) end
    end
    @error "Failed to receive after retries."
    return nothing
end

const _ZMQ_SOCKET_TYPES = Dict{String, Int}(
    "REQ" => ZMQ.REQ, "REP" => ZMQ.REP, "PUB" => ZMQ.PUB,
    "SUB" => ZMQ.SUB, "PUSH" => ZMQ.PUSH, "PULL" => ZMQ.PULL,
    "DEALER" => ZMQ.DEALER, "ROUTER" => ZMQ.ROUTER, "PAIR" => ZMQ.PAIR,
)

function _init_zmq_port_impl(port_name, port_type, address, resolved_type)
    ctx  = Sys.iswindows() ? ZMQ.Context() : state.zmq_ctx
    sock = ZMQ.Socket(ctx, resolved_type)
    ZMQ.set_linger(sock, 0)
    ZMQ.set_rcvtimeo(sock, 2000)
    ZMQ.set_sndtimeo(sock, 2000)
    port_type == "bind" ? ZMQ.bind(sock, address) : ZMQ.connect(sock, address)
    state.zmq_ports[port_name] = ZeroMQPort(sock, port_type, address, ctx)
end

function init_zmq_port(port_name::String, port_type::String, address::String, socket_type::AbstractString)
    haskey(state.zmq_ports, port_name) && return
    key = uppercase(strip(socket_type))
    _init_zmq_port_impl(port_name, port_type, address, _ZMQ_SOCKET_TYPES[key])
end

function init_zmq_port(port_name::String, port_type::String, address::String, socket_type::Integer)
    haskey(state.zmq_ports, port_name) && return
    _init_zmq_port_impl(port_name, port_type, address, Int(socket_type))
end

function terminate_zmq()
    state.cleanup_in_progress && return
    state.cleanup_in_progress = true
    seen_ctxs = Set{UInt}()
    for (name, port) in state.zmq_ports
        try ZMQ.close(port.socket) catch end
        if pointer_from_objref(port.ctx) != pointer_from_objref(state.zmq_ctx)
            ctx_ptr = UInt(pointer_from_objref(port.ctx))
            if !(ctx_ptr in seen_ctxs)
                push!(seen_ctxs, ctx_ptr)
                try ZMQ.close(port.ctx) catch end
            end
        end
    end
    empty!(state.zmq_ports)
    try ZMQ.close(state.zmq_ctx) catch end
    state.cleanup_in_progress = false
end

atexit(terminate_zmq)
Base.exit_on_sigint(false)

if !Sys.iswindows()
    const _sigterm_handler = @cfunction((_::Cint) -> exit(0), Cvoid, (Cint,))
    ccall(:signal, Ptr{Cvoid}, (Cint, Ptr{Cvoid}), 15, _sigterm_handler)
end
