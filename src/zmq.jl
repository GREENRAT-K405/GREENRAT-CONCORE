# ===================================================================
# ZeroMQ Lifecycle & Retry Loops
# ===================================================================

"""
    send_json_with_retry(port, message)

Serialize `message` to JSON and send it on `port.socket`, retrying up to
5 times with 0.5 s sleep between attempts on timeout.
"""
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

"""
    recv_json_with_retry(port) -> Any

Receive a JSON message from `port.socket`, retrying up to 5 times.
Returns `nothing` if all attempts fail.
"""
function recv_json_with_retry(port::ZeroMQPort)
    for attempt in 1:5
        try
            msg = String(ZMQ.recv(port.socket))
            return JSON.parse(msg)
        catch e
            @warn "Receive timeout (attempt $attempt/5)"
            sleep(0.5)
        end
    end
    @error "Failed to receive after retries."
    return nothing
end

# Mirrors Python: getattr(zmq, socket_type_str.upper())
# Accepts either a string name ("REQ", "REP", ...) or a raw ZMQ integer constant.
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

# Shared implementation used by both init_zmq_port dispatch methods
function _init_zmq_port_impl(port_name::String, port_type::String, address::String, resolved_type::Int)
    try
        sock = ZMQ.Socket(state.zmq_ctx, resolved_type)
        ZMQ.set_rcvtimeo(sock, 2000)
        ZMQ.set_sndtimeo(sock, 2000)
        ZMQ.set_linger(sock, 0)
        if port_type == "bind"
            ZMQ.bind(sock, address)
        else
            ZMQ.connect(sock, address)
        end
        state.zmq_ports[port_name] = ZeroMQPort(sock, port_type, address)
        @info "Initialized ZMQ port: $port_name on $address"
    catch e
        @error "Error initializing ZMQ port $port_name on $address: $e"
    end
end

"""
    init_zmq_port(port_name, port_type, address, socket_type::AbstractString)

Initialize a ZMQ socket identified by `port_name`. `socket_type` is a string
such as `"REQ"`, `"PUB"`, etc. `port_type` is either `"bind"` or `"connect"`.
"""
function init_zmq_port(port_name::String, port_type::String, address::String, socket_type::AbstractString)
    if haskey(state.zmq_ports, port_name)
        @info "ZMQ Port $port_name already initialized."
        return
    end
    key = uppercase(strip(socket_type))
    if !haskey(_ZMQ_SOCKET_TYPES, key)
        @error "Invalid ZMQ socket type string '$socket_type'. Valid types: $(join(keys(_ZMQ_SOCKET_TYPES), ", "))"
        return
    end
    _init_zmq_port_impl(port_name, port_type, address, _ZMQ_SOCKET_TYPES[key])
end

"""
    init_zmq_port(port_name, port_type, address, socket_type::Integer)

Initialize a ZMQ socket identified by `port_name`. `socket_type` is a raw
ZMQ integer constant (e.g. `ZMQ.REQ`).
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

Close all registered ZMQ sockets and the shared context. Called automatically
on process exit via `atexit`. Safe to call more than once.
"""
function terminate_zmq()
    if state.cleanup_in_progress return end
    state.cleanup_in_progress = true
    println("\nCleaning up ZMQ resources...")
    for (name, port) in state.zmq_ports
        try
            ZMQ.close(port.socket)
            println("Closed ZMQ port: $name")
        catch e
            @error "Error closing port $name: $e"
        end
    end
    empty!(state.zmq_ports)
    ZMQ.close(state.zmq_ctx)
    state.cleanup_in_progress = false
end

# Native Julia graceful teardown
atexit(terminate_zmq)

# ===================================================================
# Signal Handling: Ensure ZMQ cleanup on Ctrl+C (SIGINT) and SIGTERM
# Mirrors Python's signal.signal(SIGINT, ...) / signal.signal(SIGTERM, ...)
# ===================================================================

# SIGINT (Ctrl+C): Switch from Julia's default hard-exit to InterruptException.
# An uncaught InterruptException causes Julia to call exit(), which fires atexit(terminate_zmq).
Base.exit_on_sigint(false)

# SIGTERM (Unix only): register a C-level handler that calls Julia exit(),
# which fires atexit(terminate_zmq) before the process ends.
# On Windows SIGTERM is not standard; concorekill.bat handles termination instead.
if !Sys.iswindows()
    const _sigterm_handler = @cfunction((_::Cint) -> exit(0), Cvoid, (Cint,))
    ccall(:signal, Ptr{Cvoid}, (Cint, Ptr{Cvoid}), 15, _sigterm_handler)
end
