module ConcoreModule

using ZMQ
using JSON

export Concore, read_state!, write_state!, unchanged, init_zmq_port!, default_maxtime!

# ===================================================================
# 1. OOP Encapsulation (ZMQ & State)
# ===================================================================
mutable struct ZeroMQPort
    socket::ZMQ.Socket
    port_type::String
    address::String
end

mutable struct Concore
    inpath::String
    outpath::String
    simtime::Float64
    delay::Float64
    s::String
    olds::String
    retrycount::Int
    zmq_ports::Dict{String, ZeroMQPort}
    
    # Internal ZMQ context to manage lifecycle natively
    zmq_ctx::ZMQ.Context 

    # Constructor
    function Concore(; delay::Float64 = 0.01, inpath::String = "./in", outpath::String = "./out")
        # In a real setup, parse concore.iport / oport here
        new(inpath, outpath, 0.0, delay, "", "", 0, Dict{String, ZeroMQPort}(), ZMQ.Context())
    end
end

# ===================================================================
# 2. ZeroMQ Lifecycle Management
# ===================================================================
function init_zmq_port!(c::Concore, port_name::String, port_type::String, address::String, socket_type::Integer)
    if haskey(c.zmq_ports, port_name)
        @info "ZMQ Port $port_name already initialized."
        return
    end
    
    sock = ZMQ.Socket(c.zmq_ctx, socket_type)
    
    # Configure timeouts (ZMQ native)
    ZMQ.set_rcvtimeo(sock, 2000)
    ZMQ.set_sndtimeo(sock, 2000)
    ZMQ.set_linger(sock, 0)
    
    if port_type == "bind"
        ZMQ.bind(sock, address)
    else
        ZMQ.connect(sock, address)
    end
    
    c.zmq_ports[port_name] = ZeroMQPort(sock, port_type, address)
    @info "Initialized ZMQ port: $port_name on $address"
end

# Ensure graceful cleanup of C-bindings
function Base.close(c::Concore)
    for (name, port) in c.zmq_ports
        ZMQ.close(port.socket)
    end
    ZMQ.close(c.zmq_ctx)
end

# ===================================================================
# 3. Dynamic Parsing (The Julia Way)
# ===================================================================
# Mimics Python's ast.literal_eval. Meta.parse safely converts 
# stringified arrays "[1.0, 2.0]" into native Julia Vectors.
function safe_parse(val_str::AbstractString, default_val)
    try
        parsed = eval(Meta.parse(String(val_str)))
        return parsed
    catch
        return default_val
    end
end

# ===================================================================
# 4. Max Time (mirrors Python's default_maxtime)
# ===================================================================
# Reads maxtime from inpath*"1/concore.maxtime" if it exists,
# otherwise falls back to the provided default value.
function default_maxtime!(c::Concore, default::Float64)::Float64
    maxtime_file = c.inpath * "1/concore.maxtime"
    if isfile(maxtime_file)
        try
            return parse(Float64, strip(read(maxtime_file, String)))
        catch
        end
    end
    return default
end

# ===================================================================
# 5. Core API: Read, Write, Unchanged
# ===================================================================
function unchanged(c::Concore)
    if c.olds == c.s
        c.s = ""
        return true
    end
    c.olds = c.s
    return false
end

# Read Method (Handles both ZMQ and Files)
function read_state!(c::Concore, port_identifier, name::String, initstr_val)
    # Default fallback
    default_return = typeof(initstr_val) == String ? safe_parse(initstr_val, initstr_val) : initstr_val

    # Case 1: ZeroMQ Network Read
    if port_identifier isa String && haskey(c.zmq_ports, port_identifier)
        port = c.zmq_ports[port_identifier]
        try
            msg = String(ZMQ.recv(port.socket))
            parsed_msg = JSON.parse(msg)
            
            # Extract simtime
            if parsed_msg isa AbstractVector && length(parsed_msg) > 0 && parsed_msg[1] isa Number
                c.simtime = max(c.simtime, parsed_msg[1])
                return parsed_msg[2:end]
            end
            return parsed_msg
        catch e
            @warn "ZMQ read timeout/error on $port_identifier. Returning default."
            return default_return
        end
    end

    # Case 2: File-Based Read
    sleep(c.delay)
    file_path = joinpath("$(c.inpath)$(port_identifier)", name)
    ins = ""
    
    # Retry logic matching Python
    for attempt in 1:5
        if isfile(file_path)
            ins = strip(read(file_path, String))
            if !isempty(ins)
                break
            end
        end
        sleep(c.delay)
        c.retrycount += 1
    end

    if isempty(ins)
        c.s *= string(initstr_val)
        return default_return
    end

    c.s *= ins
    
    # Dynamic parsing
    parsed_val = safe_parse(ins, default_return)
    if parsed_val isa AbstractVector && length(parsed_val) > 0 && parsed_val[1] isa Number
        c.simtime = max(c.simtime, parsed_val[1])
        return parsed_val[2:end]
    end
    
    return parsed_val
end

# Write Method using Multiple Dispatch (Instead of Python's isinstance)
# Signature 1: Writing Arrays/Vectors
function write_state!(c::Concore, port_identifier, name::String, val::AbstractVector, delta::Real=0)
    payload = vcat([c.simtime + delta], val)
    c.simtime += delta
    _execute_write(c, port_identifier, name, payload)
end

# Signature 2: Writing Strings
function write_state!(c::Concore, port_identifier, name::String, val::String, delta::Real=0)
    sleep(2 * c.delay) # String writes wait longer, per Python logic
    _execute_write(c, port_identifier, name, val)
end

# Internal Router for writing
function _execute_write(c::Concore, port_identifier, name::String, payload)
    # ZMQ Write
    if port_identifier isa String && haskey(c.zmq_ports, port_identifier)
        port = c.zmq_ports[port_identifier]
        json_payload = JSON.json(payload)
        ZMQ.send(port.socket, json_payload)
        return
    end
    
    # File Write
    file_path = joinpath("$(c.outpath)$(port_identifier)", name)
    mkpath(dirname(file_path)) # Ensure directory exists
    
    open(file_path, "w") do io
        write(io, payload isa String ? payload : string(payload))
    end
end

end # module