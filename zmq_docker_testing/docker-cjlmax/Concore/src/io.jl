# Public API: concore_read, concore_write, unchanged, initval.
# Julia's multiple dispatch routes each call to the right transport (File, SHM, or ZMQ)
# based on the type of port_id — Integer = file/SHM, String = ZMQ.

"""
    unchanged() -> Bool

Returns `true` if no new data arrived since the last call.
Resets the accumulator on match. Mirrors Python's `concore.unchanged()`.
"""
function unchanged()
    if state.olds == state.s
        state.s = ""
        return true
    end
    state.olds = state.s
    return false
end

"""
    initval(simtime_val_str) -> Vector

Parse `[simtime, v1, v2, ...]`, store `simtime`, and return `[v1, v2, ...]`.
"""
function initval(simtime_val_str::String)
    val = safe_parse(simtime_val_str, [])
    if val isa AbstractVector && length(val) > 0
        first_el = val[1]
        if first_el isa Number
            state.simtime = Float64(first_el)
            return val[2:end]
        else
            @error "First element in initval string is not a number."
            return length(val) > 1 ? val[2:end] : []
        end
    end
    @error "initval string is not a list or is empty."
    return []
end

# --- concore_read ---

"""
    concore_read(port_id::String, name, initstr_val)

Read from a registered ZMQ port. Returns `initstr_val` if the port is missing or receive fails.
"""
function concore_read(port_id::AbstractString, name::String, initstr_val)
    default_return = initstr_val isa AbstractString ? safe_parse(initstr_val, initstr_val) : initstr_val
    if !haskey(state.zmq_ports, port_id)
        @error "No ZMQ port registered: $port_id"
        return default_return
    end
    msg = recv_json_with_retry(state.zmq_ports[port_id])
    msg === nothing && return default_return
    if msg isa AbstractVector && length(msg) > 0 && msg[1] isa Number
        state.simtime = max(state.simtime, msg[1])
        return msg[2:end]
    end
    return msg
end

"""
    concore_read(port_id::Integer, name, initstr_val)

Read from a file-based port (or SHM on Linux). Falls back to `initstr_val` on error.
"""
function concore_read(port_id::Integer, name::String, initstr_val)
    if Sys.islinux() && SHM_STATE.communication_iport == 1
        return concore_read_SM(port_id, name, initstr_val)
    end

    default_return = initstr_val isa AbstractString ? safe_parse(initstr_val, initstr_val) : initstr_val
    sleep(state.delay)
    file_path = joinpath(state.inpath * string(port_id), name)
    ins = ""

    if !isfile(file_path)
        ins = string(initstr_val)
        state.s *= ins
    else
        try
            ins = strip(Base.read(file_path, String))
        catch e
            @error "Error reading $file_path: $e. Using default value."
            return default_return
        end

        attempts = 0
        while isempty(ins) && attempts < 5
            sleep(state.delay)
            try ins = strip(Base.read(file_path, String)) catch e @warn "Retry $(attempts+1): $e" end
            attempts += 1
            state.retrycount += 1
        end

        if isempty(ins)
            @error "Max retries reached for $file_path, using default."
            return default_return
        end

        state.s *= ins
    end

    parsed_val = safe_parse(ins, default_return)
    if parsed_val isa AbstractVector && length(parsed_val) > 0 && parsed_val[1] isa Number
        state.simtime = max(state.simtime, parsed_val[1])
        return parsed_val[2:end]
    end
    return parsed_val
end

# --- concore_write ---

"""
    concore_write(port_id::String, name, val, delta=0)

Send `val` over a registered ZMQ port. Prepends `simtime + delta` for vector values.
"""
function concore_write(port_id::AbstractString, name::String, val, delta::Real=0)
    if !haskey(state.zmq_ports, port_id)
        @error "No ZMQ port registered: $port_id"
        return
    end
    payload = val isa AbstractVector ? vcat([state.simtime + delta], val) : val
    send_json_with_retry(state.zmq_ports[port_id], payload)
end

"""
    concore_write(port_id::Integer, name, val::Vector, delta=0)

Write a vector to a file-based port (or SHM). Prepends `simtime + delta`.
"""
function concore_write(port_id::Integer, name::String, val::AbstractVector, delta::Real=0)
    if Sys.islinux() && SHM_STATE.communication_oport == 1
        return concore_write_SM(port_id, name, val, delta)
    end

    file_path = joinpath(state.outpath * string(port_id), name)
    payload = vcat([state.simtime + delta], val)
    try
        mkpath(dirname(file_path))
        open(file_path, "w") do io
            Base.write(io, replace(JSON.json(payload), "\"" => "'"))
        end
    catch e
        @error "Error writing to $file_path: $e"
    end
end

"""
    concore_write(port_id::Integer, name, val::String, delta=0)

Write a raw string to a file-based port (or SHM).
"""
function concore_write(port_id::Integer, name::String, val::AbstractString, delta::Real=0)
    if Sys.islinux() && SHM_STATE.communication_oport == 1
        return concore_write_SM(port_id, name, val, delta)
    end

    file_path = joinpath(state.outpath * string(port_id), name)
    sleep(2 * state.delay)
    try
        mkpath(dirname(file_path))
        open(file_path, "w") do io Base.write(io, val) end
    catch e
        @error "Error writing to $file_path: $e"
    end
end

"""Catch-all for unsupported value types. Logs an error."""
function concore_write(port_id::Integer, name::String, val, delta::Real=0)
    file_path = joinpath(state.outpath * string(port_id), name)
    @error "File write to $file_path must have list or str value, got $(typeof(val))"
end
