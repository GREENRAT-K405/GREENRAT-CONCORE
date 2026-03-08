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
    if val isa AbstractVector && !isempty(val) && val[1] isa Number
        state.simtime = Float64(val[1])
        return val[2:end]
    end
    return []
end

# ZMQ read (port_id is a String)
function concore_read(port_id::AbstractString, name::String, initstr_val)
    default_return = initstr_val isa AbstractString ? safe_parse(initstr_val, initstr_val) : initstr_val
    !haskey(state.zmq_ports, port_id) && return default_return
    msg = recv_json_with_retry(state.zmq_ports[port_id])
    msg === nothing && return default_return
    if msg isa AbstractVector && !isempty(msg) && msg[1] isa Number
        state.simtime = max(state.simtime, msg[1])
        return msg[2:end]
    end
    return msg
end

# File / SHM read (port_id is an Integer)
function concore_read(port_id::Integer, name::String, initstr_val)
    Sys.islinux() && SHM_STATE.communication_iport == 1 && return concore_read_SM(port_id, name, initstr_val)

    default_return = initstr_val isa AbstractString ? safe_parse(initstr_val, initstr_val) : initstr_val
    sleep(state.delay)
    file_path = joinpath(state.inpath * string(port_id), name)
    ins = ""

    if !isfile(file_path)
        ins = string(initstr_val)
        state.s *= ins
    else
        try ins = strip(Base.read(file_path, String)) catch; return default_return end
        attempts = 0
        while isempty(ins) && attempts < 5
            sleep(state.delay)
            try ins = strip(Base.read(file_path, String)) catch end
            attempts += 1; state.retrycount += 1
        end
        isempty(ins) && return default_return
        state.s *= ins
    end

    parsed = safe_parse(ins, default_return)
    if parsed isa AbstractVector && !isempty(parsed) && parsed[1] isa Number
        state.simtime = max(state.simtime, parsed[1])
        return parsed[2:end]
    end
    return parsed
end

# ZMQ write (port_id is a String)
function concore_write(port_id::AbstractString, name::String, val, delta::Real=0)
    !haskey(state.zmq_ports, port_id) && return
    payload = val isa AbstractVector ? vcat([state.simtime + delta], val) : val
    send_json_with_retry(state.zmq_ports[port_id], payload)
end

# File / SHM write — vector
function concore_write(port_id::Integer, name::String, val::AbstractVector, delta::Real=0)
    Sys.islinux() && SHM_STATE.communication_oport == 1 && return concore_write_SM(port_id, name, val, delta)
    file_path = joinpath(state.outpath * string(port_id), name)
    payload   = vcat([state.simtime + delta], val)
    mkpath(dirname(file_path))
    open(file_path, "w") do io
        Base.write(io, replace(JSON.json(payload), "\"" => "'"))
    end
end

# File / SHM write — string
function concore_write(port_id::Integer, name::String, val::AbstractString, delta::Real=0)
    Sys.islinux() && SHM_STATE.communication_oport == 1 && return concore_write_SM(port_id, name, val, delta)
    file_path = joinpath(state.outpath * string(port_id), name)
    sleep(2 * state.delay)
    mkpath(dirname(file_path))
    open(file_path, "w") do io Base.write(io, val) end
end

# Catch-all for unsupported types
function concore_write(port_id::Integer, name::String, val, delta::Real=0)
    @error "Value for port $port_id must be an Array or String, got $(typeof(val))"
end


# shm.jl - Leading Integer Extraction
function extract_numeric(str::String)::Int
    # Regex: Look for one or more digits at the very beginning of the string
    m = match(r"^(\d+)", str) 
    
    # If no number is found, return -1 (meaning File-Method fallback)
    m === nothing && return -1
    
    # Otherwise, extract the number to use as the Kernel C-pointer Key
    n = parse(Int, m.captures[1])
    return n <= 0 ? -1 : n
end
unchanged()
initval(simtime_val_str)

state.simtime