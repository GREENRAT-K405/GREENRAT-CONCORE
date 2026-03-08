# ZeroMQ transport — socket lifecycle, send/receive with retries, and signal handling.

"""Send `message` as JSON on `port.socket`, retrying up to 5 times on timeout."""
function send_json_with_retry(port::ZeroMQPort, message)
    json_msg = JSON.json(message)
    for attempt in 1:5
        try
            ZMQ.send(port.socket, json_msg)
            return
        catch e
            @warn "Send timeout (attempt $attempt/5)"
            sleep(0.5)
        end
    end
    @error "Failed to send after retries."
end

"""Receive a JSON message from `port.socket`, retrying up to 5 times. Returns `nothing` on failure."""
function recv_json_with_retry(port::ZeroMQPort)
    for attempt in 1:5
        try
            msg = String(ZMQ.recv(port.socket))
            return JSON.parse(msg)
        catch e
            @warn "Receive timeout (attempt $attempt/5): $e"
            sleep(0.5)
        end
    end
    @error "Failed to receive after retries."
    return nothing
end

# Maps socket type strings ("REQ", "PUB", etc.) to ZMQ integer constants.
const _ZMQ_SOCKET_TYPES = Dict{String, Int}(
    "REQ"    => ZMQ.REQ,
    "REP"    => ZMQ.REP,
    "PUB"    => ZMQ.PUB,
    "SUB"    => ZMQ.SUB,
    "PUSH"   => ZMQ.PUSH,
    "PULL"   => ZMQ.PULL,
    "DEALER" => ZMQ.DEALER,
    "ROUTER" => ZMQ.ROUTER,
    "PAIR"   => ZMQ.PAIR,
)

function _init_zmq_port_impl(port_name::String, port_type::String, address::String, resolved_type::Int)
    try
        # Windows needs a fresh context per socket to avoid hangs when setting timeouts.
        ctx = Sys.iswindows() ? ZMQ.Context() : state.zmq_ctx
        sock = ZMQ.Socket(ctx, resolved_type)
        ZMQ.set_linger(sock, 0)
        ZMQ.set_rcvtimeo(sock, 2000)
        ZMQ.set_sndtimeo(sock, 2000)
        if port_type == "bind"
            ZMQ.bind(sock, address)
        else
            ZMQ.connect(sock, address)
        end
        state.zmq_ports[port_name] = ZeroMQPort(sock, port_type, address, ctx)
        @info "Initialized ZMQ port: $port_name on $address"
    catch e
        @error "Error initializing ZMQ port $port_name on $address: $e"
    end
end

"""
    init_zmq_port(port_name, port_type, address, socket_type::String)

Open a ZMQ socket. `socket_type` is a string like `"REQ"`, `"PUB"`, etc.
`port_type` is either `"bind"` or `"connect"`.
"""
function init_zmq_port(port_name::String, port_type::String, address::String, socket_type::AbstractString)
    if haskey(state.zmq_ports, port_name)
        @info "ZMQ Port $port_name already initialized."
        return
    end
    key = uppercase(strip(socket_type))
    if !haskey(_ZMQ_SOCKET_TYPES, key)
        @error "Invalid ZMQ socket type '$socket_type'. Valid: $(join(keys(_ZMQ_SOCKET_TYPES), ", "))"
        return
    end
    _init_zmq_port_impl(port_name, port_type, address, _ZMQ_SOCKET_TYPES[key])
end

"""
    init_zmq_port(port_name, port_type, address, socket_type::Integer)

Same as above but accepts a raw ZMQ constant (e.g. `ZMQ.REQ`).
"""
function init_zmq_port(port_name::String, port_type::String, address::String, socket_type::Integer)
    if haskey(state.zmq_ports, port_name)
        @info "ZMQ Port $port_name already initialized."
        return
    end
    _init_zmq_port_impl(port_name, port_type, address, Int(socket_type))
end

"""
    terminate_zmq()

Close all ZMQ sockets and contexts. Registered via `atexit` — runs automatically on exit.
"""
function terminate_zmq()
    if state.cleanup_in_progress return end
    state.cleanup_in_progress = true
    println("\nCleaning up ZMQ resources...")
    seen_ctxs = Set{UInt}()
    for (name, port) in state.zmq_ports
        try
            ZMQ.close(port.socket)
            println("Closed ZMQ port: $name")
        catch e
            @error "Error closing port $name: $e"
        end
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

# Catch Ctrl+C gracefully so atexit hooks (terminate_zmq) still run.
Base.exit_on_sigint(false)

# On Unix, handle SIGTERM (sent by `docker stop`) with a clean exit.
if !Sys.iswindows()
    const _sigterm_handler = @cfunction((_::Cint) -> exit(0), Cvoid, (Cint,))
    ccall(:signal, Ptr{Cvoid}, (Cint, Ptr{Cvoid}), 15, _sigterm_handler)
end
