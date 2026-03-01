module Concore

using ZMQ
using JSON

export concore_read, concore_write, unchanged, init_zmq_port, terminate_zmq, default_maxtime, tryparam, initval, iport, oport

# ===================================================================
# 1. Internal State Management
# ===================================================================
mutable struct ZeroMQPort
    socket::ZMQ.Socket
    port_type::String
    address::String
end

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

# Global state instance (matches Python's module-level variables)
const state = ConcoreState(
    "./in", "./out", 0.0, 1.0, "", "", 0,
    Dict{String, ZeroMQPort}(), ZMQ.Context(),
    Dict{String, Any}(), false,
    Dict{String, Any}(), Dict{String, Any}(),
    100.0  # mirrors Python's default_maxtime(100)
)

# Write concorekill.bat on Windows so batch run scripts can terminate this process by PID
# Mirrors Python: if hasattr(sys, 'getwindowsversion'): open("concorekill.bat","w").write(...)
if Sys.iswindows()
    try
        open("concorekill.bat", "w") do f
            write(f, "taskkill /F /PID $(getpid())\n")
        end
    catch e
        @warn "Could not write concorekill.bat: $e"
    end
end

# ===================================================================
# 2. Security & Safe Parsing
# ===================================================================
# Replaces dangerous `eval(Meta.parse())` with a strict JSON-based parser.
# Python lists like `[1, 'foo']` use single quotes. This normalizes them 
# to double quotes so JSON.parse can safely handle them without executing code.
function safe_parse(val_str::AbstractString, default_val)
    clean_str = replace(val_str, "'" => "\"")
    try
        return JSON.parse(clean_str)
    catch
        return default_val
    end
end

function safe_literal_eval(filename::String, default_val)
    try
        return safe_parse(Base.read(filename, String), default_val)
    catch
        return default_val
    end
end

# ===================================================================
# 3. Parameter Handling (concore.params)
# ===================================================================
function parse_params(sparams::String)::Dict{String, Any}
    params = Dict{String, Any}()
    s = strip(sparams)
    if isempty(s) return params end

    # Full dict literal
    if startswith(s, "{") && endswith(s, "}")
        val = safe_parse(s, nothing)
        if val isa Dict
            return val
        end
    end

    for item in split(s, ";")
        if occursin("=", item)
            parts = split(item, "="; limit=2)
            key = strip(parts[1])
            val_str = strip(parts[2])
            params[key] = safe_parse(val_str, val_str)
        end
    end
    return params
end

function load_params!()
    params_file = joinpath(state.inpath * "1", "concore.params")
    if isfile(params_file)
        try
            sparams = strip(Base.read(params_file, String))
            if startswith(sparams, "\"") && endswith(sparams, "\"")
                sparams = sparams[2:end-1]
            end
            state.params = parse_params(sparams)
        catch e
            @warn "Error reading concore.params: $e"
            state.params = Dict{String, Any}()
        end
    end
end

# Initialize parameters on module load
load_params!()

# ===================================================================
# Load concore.iport / concore.oport at startup
# Mirrors Python: iport = safe_literal_eval("concore.iport", {})
#                 oport = safe_literal_eval("concore.oport", {})
# These files are in the component's working directory (not inpath).
# ===================================================================
function load_ports!()
    raw_iport = safe_literal_eval("concore.iport", Dict{String, Any}())
    raw_oport = safe_literal_eval("concore.oport", Dict{String, Any}())
    # safe_parse returns JSON-parsed types; normalise keys to String
    if raw_iport isa Dict
        state.iport = Dict{String, Any}(string(k) => v for (k, v) in raw_iport)
    end
    if raw_oport isa Dict
        state.oport = Dict{String, Any}(string(k) => v for (k, v) in raw_oport)
    end
end

load_ports!()

# Accessor functions exported so callers can use iport() / oport()
iport() = state.iport
oport() = state.oport

function tryparam(n::String, i)
    return get(state.params, n, i)
end

function default_maxtime(default)
    maxtime_file = joinpath(state.inpath * "1", "concore.maxtime")
    # Mirror Python side effect: concore.maxtime = ... so state.maxtime is readable after the call
    state.maxtime = Float64(safe_literal_eval(maxtime_file, default))
    return state.maxtime
end

# ===================================================================
# 4. ZeroMQ Lifecycle & Retry Loops
# ===================================================================
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

function init_zmq_port(port_name::String, port_type::String, address::String, socket_type::Union{AbstractString, Integer})
    if haskey(state.zmq_ports, port_name)
        @info "ZMQ Port $port_name already initialized."
        return
    end
    # Resolve string → integer constant (case-insensitive, mirrors Python getattr(zmq, ...))
    resolved_type::Int = if socket_type isa AbstractString
        key = uppercase(strip(socket_type))
        if !haskey(_ZMQ_SOCKET_TYPES, key)
            @error "Invalid ZMQ socket type string '$socket_type'. Valid types: $(join(keys(_ZMQ_SOCKET_TYPES), \", \"))"
            return
        end
        _ZMQ_SOCKET_TYPES[key]
    else
        Int(socket_type)
    end
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

# ===================================================================
# 5. Core API: Read, Write, Initval, Unchanged
# ===================================================================
function unchanged()
    if state.olds == state.s
        state.s = ""
        return true
    end
    state.olds = state.s
    return false
end

function initval(simtime_val_str::String)
    val = safe_parse(simtime_val_str, [])
    if val isa AbstractVector && length(val) > 0
        first_el = val[1]
        if first_el isa Number
            state.simtime = Float64(first_el)
            return val[2:end]
        else
            @error "Error: First element in initval string is not a number."
            return length(val) > 1 ? val[2:end] : []
        end
    end
    @error "Error: initval string is not a list or is empty."
    return []
end

function concore_read(port_identifier, name::String, initstr_val)
    default_return = typeof(initstr_val) <: AbstractString ? safe_parse(initstr_val, initstr_val) : initstr_val
    
    # Case 1: ZMQ Port
    if port_identifier isa AbstractString && haskey(state.zmq_ports, port_identifier)
        port = state.zmq_ports[port_identifier]
        msg = recv_json_with_retry(port)
        if msg !== nothing
            if msg isa AbstractVector && length(msg) > 0 && msg[1] isa Number
                state.simtime = max(state.simtime, msg[1])
                return msg[2:end]
            end
            return msg
        else
            return default_return
        end
    end
    
    # Case 2: File Port
    port_num = try parse(Int, string(port_identifier)) catch; return default_return end
    sleep(state.delay)
    file_path = joinpath(state.inpath * string(port_num), name)
    
    ins = ""
    for attempt in 1:6
        if isfile(file_path)
            try
                ins = strip(Base.read(file_path, String))
                if !isempty(ins) break end
            catch
            end
        end
        if attempt < 6
            sleep(state.delay)
        end
        # Mirror Python: retrycount only increments on actual retries (after the first attempt)
        if attempt > 1
            state.retrycount += 1
        end
    end
    
    if isempty(ins)
        state.s *= string(initstr_val)
        return default_return
    end
    
    state.s *= ins
    parsed_val = safe_parse(ins, default_return)
    
    if parsed_val isa AbstractVector && length(parsed_val) > 0 && parsed_val[1] isa Number
        state.simtime = max(state.simtime, parsed_val[1])
        return parsed_val[2:end]
    end
    return parsed_val
end

function concore_write(port_identifier, name::String, val, delta::Real=0)
    # Issue #385 fix: Do not mutate internal simtime.
    payload = val isa AbstractVector ? vcat([state.simtime + delta], val) : val
    
    # Case 1: ZMQ Port
    if port_identifier isa AbstractString && haskey(state.zmq_ports, port_identifier)
        port = state.zmq_ports[port_identifier]
        send_json_with_retry(port, payload)
        return
    end
    
    # Case 2: File Port
    port_num = try parse(Int, string(port_identifier)) catch; return end
    file_path = joinpath(state.outpath * string(port_num), name)
    
    if val isa AbstractString
        sleep(2 * state.delay)
    end
    
    try
        mkpath(dirname(file_path))
        open(file_path, "w") do io
            # Write JSON-like representation for arrays, otherwise plain string
            out_str = payload isa AbstractVector ? replace(JSON.json(payload), "\"" => "'") : string(payload)
            Base.write(io, out_str)
        end
    catch e
        @error "Error writing to $file_path: $e"
    end
end

end # module