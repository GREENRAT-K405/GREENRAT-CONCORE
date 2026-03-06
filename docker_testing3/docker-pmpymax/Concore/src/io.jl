# ===================================================================
# Core API: Read, Write, Initval, Unchanged
# ===================================================================

"""
    unchanged() -> Bool

Return `true` if no new data has arrived since the last call (i.e., the
accumulated read string `s` is the same as the previous call). Resets
the accumulator on match. Mirrors Python's `concore.unchanged()`.
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

Parse `simtime_val_str` as a `[simtime, v1, v2, ...]` list, store
`simtime` in `state.simtime`, and return `[v1, v2, ...]`.
Mirrors Python's `concore.initval`.
"""
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

# ---------------------------------------------------------------
# concore_read — three dispatch methods
# ---------------------------------------------------------------

"""
    concore_read(port_id::AbstractString, name, initstr_val)

Read from a registered ZMQ port (identified by the string `port_id`).
Returns `initstr_val` (parsed) if the port is not registered or receive fails.
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

Read from a file-based port (or shared-memory port on Linux).
`port_id` is the integer port number; the file is read from
`state.inpath * string(port_id) / name`.
Returns `initstr_val` (parsed) on error or missing file.
"""
function concore_read(port_id::Integer, name::String, initstr_val)
    # Shared Memory path (Linux only, mirrors concore.hpp::read())
    if Sys.islinux() && SHM_STATE.communication_iport == 1
        return concore_read_SM(port_id, name, initstr_val)
    end

    # ---- File Method (FM) path ----
    default_return = initstr_val isa AbstractString ? safe_parse(initstr_val, initstr_val) : initstr_val
    sleep(state.delay)
    file_path = joinpath(state.inpath * string(port_id), name)

    ins = ""

    if !isfile(file_path)
        # Mirror Python FileNotFoundError branch exactly:
        # set ins = str(initstr_val), update s, then fall through to the shared
        # parse + simtime-strip block below — NOT an early return.
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
        max_retries = 5
        while isempty(ins) && attempts < max_retries
            sleep(state.delay)
            try
                ins = strip(Base.read(file_path, String))
            catch e
                @warn "Retry $(attempts + 1): Error reading $file_path - $e"
            end
            attempts += 1
            state.retrycount += 1
        end

        if isempty(ins)
            @error "Max retries reached for $file_path, using default value."
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

# ---------------------------------------------------------------
# concore_write — four dispatch methods
# ---------------------------------------------------------------

"""
    concore_write(port_id::AbstractString, name, val, delta=0)

Send `val` over a registered ZMQ port (identified by the string `port_id`).
For vector `val`, prepends `simtime + delta` before sending.
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
    concore_write(port_id::Integer, name, val::AbstractVector, delta=0)

Write a vector to a file-based port (or shared-memory on Linux).
Prepends `simtime + delta` and serializes as a JSON array.
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
    concore_write(port_id::Integer, name, val::AbstractString, delta=0)

Write a raw string to a file-based port (or shared-memory on Linux).
Sleeps for `2 * state.delay` before writing (mirrors Python).
"""
function concore_write(port_id::Integer, name::String, val::AbstractString, delta::Real=0)
    if Sys.islinux() && SHM_STATE.communication_oport == 1
        return concore_write_SM(port_id, name, val, delta)
    end

    file_path = joinpath(state.outpath * string(port_id), name)
    sleep(2 * state.delay)
    try
        mkpath(dirname(file_path))
        open(file_path, "w") do io
            Base.write(io, val)
        end
    catch e
        @error "Error writing to $file_path: $e"
    end
end

"""
    concore_write(port_id::Integer, name, val, delta=0)

Catch-all for unsupported value types. Logs an error.
Mirrors Python's early error return for non-list, non-str values.
"""
function concore_write(port_id::Integer, name::String, val, delta::Real=0)
    file_path = joinpath(state.outpath * string(port_id), name)
    @error "File write to $file_path must have list or str value, got $(typeof(val))"
end
