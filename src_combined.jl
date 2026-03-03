"""
    Concore

Julia implementation of the Concore communication library.

Concore provides lightweight inter-component communication for simulation
frameworks via three transport backends:

- **File Method (FM)**: shared filesystem paths, works everywhere
- **Shared Memory (SM)**: POSIX System V SHM via `ccall`, Linux only
- **ZeroMQ**: socket-based transport for distributed/networked components

# Quickstart

```julia
using Concore

# Read a value from port 1, variable "x", defaulting to [0.0]
x = concore_read(1, "x", "[0, 0.0]")

# Write a value to port 1, variable "y"
concore_write(1, "y", [1.0, 2.0])

# Check if inputs have changed since last iteration
if !unchanged()
    # process new data ...
end
```

See the individual function docstrings for full API documentation.
"""
module Concore

using ZMQ
using JSON

# ---------------------------------------------------------------
# Public API exports
# ---------------------------------------------------------------
export concore_read, concore_write,
       unchanged, initval,
       init_zmq_port, terminate_zmq,
       default_maxtime, tryparam,
       iport, oport

# ---------------------------------------------------------------
# Source files (order matters: later files depend on earlier ones)
# ---------------------------------------------------------------
include("state.jl")    # Structs + global state instances
include("params.jl")   # safe_parse, parse_params, load_params!, tryparam, default_maxtime
include("ports.jl")    # load_ports!, iport(), oport()
include("zmq.jl")      # init_zmq_port, terminate_zmq, send/recv helpers, signal handling
include("shm.jl")      # Shared memory (Linux only): create/get/cleanup + read_SM/write_SM
include("io.jl")       # concore_read, concore_write, unchanged, initval

# ---------------------------------------------------------------
# Module initialisation (runs once when `using Concore` is called)
# ---------------------------------------------------------------
load_params!()          # populate state.params from concore.params file
load_ports!()           # populate state.iport / state.oport
_init_shm_from_ports!() # set up SHM segments if numeric port keys are present

end # module Concore
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
# ===================================================================
# Security & Safe Parsing
# ===================================================================
# Replaces dangerous `eval(Meta.parse())` with a strict JSON-based parser.
# Python lists like `[1, 'foo']` use single quotes. This normalizes them
# to double quotes so JSON.parse can safely handle them without executing code.

"""
    safe_parse(val_str, default_val)

Parse `val_str` as JSON, normalising Python-style single-quote strings to
double quotes first. Returns `default_val` on any parse failure.
Never calls `eval`.
"""
function safe_parse(val_str::AbstractString, default_val)
    clean_str = replace(val_str, "'" => "\"")
    try
        return JSON.parse(clean_str)
    catch
        return default_val
    end
end

"""
    safe_literal_eval(filename, default_val)

Read `filename` and parse its content with `safe_parse`.
Returns `default_val` if the file is missing or unparseable.
"""
function safe_literal_eval(filename::String, default_val)
    try
        return safe_parse(Base.read(filename, String), default_val)
    catch
        return default_val
    end
end

# ===================================================================
# Parameter Handling (concore.params)
# ===================================================================

"""
    parse_params(sparams) -> Dict{String, Any}

Parse the concore parameter string. Accepts either:
- A JSON dict literal: `{"k": v, ...}`
- A semicolon-separated key=value list: `k1=v1; k2=v2`
"""
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

"""
    load_params!()

Read `concore.params` from the input directory and populate `state.params`.
Called once on module load; call again to refresh during a simulation.
"""
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

"""
    tryparam(name, default)

Return the value of parameter `name` from `state.params`, or `default`
if the parameter is absent. Mirrors Python's `concore.tryparam`.
"""
function tryparam(n::String, i)
    return get(state.params, n, i)
end

"""
    default_maxtime(default) -> Float64

Read `concore.maxtime` from the input directory and return it.
Stores the result in `state.maxtime` as a side-effect (mirrors Python).
Falls back to `default` if the file is missing or unparseable.
"""
function default_maxtime(default)
    maxtime_file = joinpath(state.inpath * "1", "concore.maxtime")
    state.maxtime = Float64(safe_literal_eval(maxtime_file, default))
    return state.maxtime
end
# ===================================================================
# Port Configuration (concore.iport / concore.oport)
# ===================================================================
# Mirrors Python: iport = safe_literal_eval("concore.iport", {})
#                 oport = safe_literal_eval("concore.oport", {})
# These files live in the component's working directory (not inpath).

"""
    load_ports!()

Read `concore.iport` and `concore.oport` from the working directory and
populate `state.iport` / `state.oport`. Called once on module load.
"""
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

"""
    iport() -> Dict{String, Any}

Return the current input-port map loaded from `concore.iport`.
"""
iport() = state.iport

"""
    oport() -> Dict{String, Any}

Return the current output-port map loaded from `concore.oport`.
"""
oport() = state.oport
# ===================================================================
# Shared Memory (Linux only — mirrors concore.hpp)
# ===================================================================
#
# Architecture:
#   - The *writer* (oport side) calls create_shared_memory(key):
#       shmget(key, 256, IPC_CREAT | 0666)  → shmId_create
#       shmat(shmId_create, NULL, 0)        → sharedData_create ptr
#
#   - The *reader* (iport side) calls get_shared_memory(key):
#       Retries shmget(key, 256, 0666) up to MAX_RETRY times (waits for writer).
#       shmat(shmId_get, NULL, 0)           → sharedData_get ptr
#
#   - write_SM writes a formatted string into sharedData_create.
#   - read_SM  reads the string from sharedData_get.
#
#   - Cleanup (atexit) calls shmdt + shmctl(IPC_RMID) on both segments.
#
# Key resolution (mirrors ExtractNumeric in concore.hpp):
#   iport / oport map keys that START with a positive integer digit sequence
#   are treated as SM keys. If the key is absent or <= 0, fall back to FM.

"""
    extract_numeric(str) -> Int

Mirrors C++ `ExtractNumeric`: returns the leading positive integer from `str`,
or -1 if none exists (i.e., non-numeric prefix or value ≤ 0).
"""
function extract_numeric(str::String)::Int
    m = match(r"^(\d+)", str)
    m === nothing && return -1
    n = parse(Int, m.captures[1])
    n <= 0 && return -1
    return n
end

if Sys.islinux()
    """
        _shm_read_string(ptr, maxlen) -> String

    Safe equivalent of C++ `std::string(ptr, strnlen(ptr, maxlen))`.
    Scans byte-by-byte up to `maxlen` bytes and stops at the first NUL,
    just like strnlen. This avoids the pitfall of `unsafe_string(ptr, n)`
    which reads exactly n bytes regardless of embedded NUL characters.
    """
    function _shm_read_string(ptr::Ptr{Cchar}, maxlen::Int)::String
        buf = UInt8[]
        for i in 0:(maxlen - 1)
            b = unsafe_load(Ptr{UInt8}(ptr + i))
            b == 0x00 && break
            push!(buf, b)
        end
        return String(buf)
    end

    """
        create_shared_memory(key)

    Creates a 256-byte SHM segment with `key` and attaches it as the *writer*
    (`sharedData_create`). Mirrors `Concore::createSharedMemory(key_t key)`.
    """
    function create_shared_memory(key::Int)
        id = ccall(:shmget, Cint, (Cint, Csize_t, Cint),
                   Cint(key), Csize_t(SHM_SIZE), Cint(IPC_CREAT | 0o666))
        if id == -1
            @error "SHM: Failed to create shared memory segment (key=$key)."
            return
        end
        SHM_STATE.shmId_create = id

        ptr = ccall(:shmat, Ptr{Cchar}, (Cint, Ptr{Cvoid}, Cint),
                    id, C_NULL, Cint(0))
        if ptr == Ptr{Cchar}(-1)
            @error "SHM: Failed to attach shared memory segment (key=$key)."
            SHM_STATE.sharedData_create = Ptr{Cchar}(0)
        else
            SHM_STATE.sharedData_create = ptr
        end
    end

    """
        get_shared_memory(key)

    Waits for the writer process to create the SHM segment, then attaches as
    the *reader* (`sharedData_get`). Mirrors `Concore::getSharedMemory(key_t key)`.
    Up to 100 retries with 1-second sleep between attempts.
    """
    function get_shared_memory(key::Int)
        MAX_RETRY = 100
        id = Cint(-1)
        for retry in 1:MAX_RETRY
            id = ccall(:shmget, Cint, (Cint, Csize_t, Cint),
                       Cint(key), Csize_t(SHM_SIZE), Cint(0o666))
            if id != Cint(-1)
                break
            end
            println("Shared memory does not exist. Make sure the writer process is running.")
            sleep(1)
        end

        if id == Cint(-1)
            @error "SHM: Failed to get shared memory segment after $MAX_RETRY retries (key=$key)."
            return
        end
        SHM_STATE.shmId_get = id

        ptr = ccall(:shmat, Ptr{Cchar}, (Cint, Ptr{Cvoid}, Cint),
                    id, C_NULL, Cint(0))
        if ptr == Ptr{Cchar}(-1)
            @error "SHM: Failed to attach shared memory segment (key=$key)."
            SHM_STATE.sharedData_get = Ptr{Cchar}(0)
        else
            SHM_STATE.sharedData_get = ptr
        end
    end

    """
        cleanup_shared_memory()

    Detaches and removes both SHM segments. Called on process exit.
    Mirrors the `~Concore()` destructor in concore.hpp.
    """
    function cleanup_shared_memory()
        if SHM_STATE.communication_oport == 1 && SHM_STATE.sharedData_create != Ptr{Cchar}(0)
            ccall(:shmdt, Cint, (Ptr{Cvoid},), SHM_STATE.sharedData_create)
            SHM_STATE.sharedData_create = Ptr{Cchar}(0)
        end
        if SHM_STATE.communication_iport == 1 && SHM_STATE.sharedData_get != Ptr{Cchar}(0)
            ccall(:shmdt, Cint, (Ptr{Cvoid},), SHM_STATE.sharedData_get)
            SHM_STATE.sharedData_get = Ptr{Cchar}(0)
        end
        if SHM_STATE.shmId_create != -1
            ccall(:shmctl, Cint, (Cint, Cint, Ptr{Cvoid}),
                  SHM_STATE.shmId_create, Cint(IPC_RMID), C_NULL)
            SHM_STATE.shmId_create = Int32(-1)
        end
    end

    atexit(cleanup_shared_memory)
end # Sys.islinux()

# ===================================================================
# SHM Initialisation from iport / oport (called after load_ports!)
# Mirrors the constructor logic in concore.hpp:
#
#   int iport_number = ExtractNumeric(iport.begin()->first);
#   int oport_number = ExtractNumeric(oport.begin()->first);
#   if (oport_number != -1) { communication_oport = 1; createSharedMemory(oport_number); }
#   if (iport_number != -1) { communication_iport = 1; getSharedMemory(iport_number); }
# ===================================================================
function _init_shm_from_ports!()
    Sys.islinux() || return   # SHM is Linux-only, just like the C++ #ifdef __linux__

    oport_number = -1
    if !isempty(state.oport)
        first_key = first(keys(state.oport))
        oport_number = extract_numeric(string(first_key))
    end

    iport_number = -1
    if !isempty(state.iport)
        first_key = first(keys(state.iport))
        iport_number = extract_numeric(string(first_key))
    end

    if oport_number != -1
        SHM_STATE.communication_oport = 1
        create_shared_memory(oport_number)
    end

    if iport_number != -1
        SHM_STATE.communication_iport = 1
        get_shared_memory(iport_number)
    end
end

# ===================================================================
# Shared Memory I/O  (read_SM / write_SM)
# Mirrors read_SM / write_SM in concore.hpp.
# ===================================================================
if Sys.islinux()
    """
        concore_read_SM(port_id, name, initstr_val)

    Read a value from the shared memory segment attached to the iport.
    Mirrors `Concore::read_SM(int port, string name, string initstr)`.
    Falls back to `initstr_val` when the segment is empty or unavailable.
    Returns the data vector with simtime stripped (same as concore_read file path).
    """
    function concore_read_SM(port_id::Integer, name::String, initstr_val)
        default_return = initstr_val isa AbstractString ? safe_parse(initstr_val, initstr_val) : initstr_val
        sleep(state.delay)

        ins = ""
        try
            if SHM_STATE.shmId_get != Cint(-1) && SHM_STATE.sharedData_get != Ptr{Cchar}(0)
                ins = _shm_read_string(SHM_STATE.sharedData_get, SHM_SIZE)
                if isempty(ins)
                    throw(ErrorException("SHM buffer empty"))
                end
            else
                throw(ErrorException("SHM not initialised"))
            end
        catch
            ins = string(initstr_val)
        end

        retry = 0
        MAX_RETRY = 100
        while isempty(ins) && retry < MAX_RETRY
            sleep(state.delay)
            try
                if SHM_STATE.shmId_get != Cint(-1) && SHM_STATE.sharedData_get != Ptr{Cchar}(0)
                    ins = _shm_read_string(SHM_STATE.sharedData_get, SHM_SIZE)
                    state.retrycount += 1
                else
                    state.retrycount += 1
                    throw(ErrorException("SHM not initialised"))
                end
            catch
                println("Read error")
            end
            retry += 1
        end

        state.s *= ins

        parsed_val = safe_parse(ins, default_return)
        if parsed_val isa AbstractVector && length(parsed_val) > 0 && parsed_val[1] isa Number
            state.simtime = max(state.simtime, parsed_val[1])
            return parsed_val[2:end]
        end
        return parsed_val
    end

    """
        concore_write_SM(port_id, name, val::AbstractVector, delta=0)

    Write a vector value to the shared memory segment attached to the oport.
    Mirrors `Concore::write_SM(int port, string name, vector<double> val, int delta)`.
    """
    function concore_write_SM(port_id::Integer, name::String, val::AbstractVector, delta::Real=0)
        try
            if SHM_STATE.shmId_create != -1 && SHM_STATE.sharedData_create != Ptr{Cchar}(0)
                payload = vcat([state.simtime + delta], val)
                result = "[" * join(payload, ",") * "]"
                nbytes = min(length(result), SHM_SIZE - 1)
                unsafe_copyto!(SHM_STATE.sharedData_create,
                               pointer(Vector{Cchar}(codeunits(result))),
                               nbytes)
                unsafe_store!(SHM_STATE.sharedData_create + nbytes, Cchar(0))
            else
                throw(ErrorException("SHM not initialised"))
            end
        catch e
            println("skipping +$(state.outpath)$(port_id) /$name")
        end
    end

    """
        concore_write_SM(port_id, name, val::AbstractString, delta=0)

    Write a string value to the shared memory segment attached to the oport.
    """
    function concore_write_SM(port_id::Integer, name::String, val::AbstractString, delta::Real=0)
        sleep(2 * state.delay)
        try
            if SHM_STATE.shmId_create != -1 && SHM_STATE.sharedData_create != Ptr{Cchar}(0)
                nbytes = min(length(val), SHM_SIZE - 1)
                unsafe_copyto!(SHM_STATE.sharedData_create,
                               pointer(Vector{Cchar}(codeunits(val))),
                               nbytes)
                unsafe_store!(SHM_STATE.sharedData_create + nbytes, Cchar(0))
            else
                throw(ErrorException("SHM not initialised"))
            end
        catch e
            println("skipping +$(state.outpath)$(port_id) /$name")
        end
    end
end # Sys.islinux()
# ===================================================================
# State Structs & Global Instances
# ===================================================================

"""
    ZeroMQPort

Holds a ZMQ socket together with its connection metadata.
"""
mutable struct ZeroMQPort
    socket::ZMQ.Socket
    port_type::String
    address::String
end

# ===================================================================
# Shared Memory State (Linux only — mirrors concore.hpp)
# ===================================================================
#
# concore.hpp uses POSIX System V SHM (shmget / shmat / shmdt / shmctl).
# We replicate the same logic via ccall so the Julia process can talk to
# C++ counterparts sharing the same SHM key.
#
# Communication mode: 0 = File Method (FM), 1 = Shared Memory (SM)

"""
    ShmState

Mirrors the SHM fields of the C++ `Concore` class.
Only meaningful on Linux; fields are initialised to sentinel values
(id = -1, ptr = NULL, mode = 0) everywhere else.
"""
mutable struct ShmState
    # IDs returned by shmget (-1 = not initialised)
    shmId_create::Int32        # used by the *writer* (oport)
    shmId_get::Int32           # used by the *reader* (iport)

    # Pointers returned by shmat (Ptr{Cchar}(0) = not attached)
    sharedData_create::Ptr{Cchar}
    sharedData_get::Ptr{Cchar}

    # Mode flags (0 = FM, 1 = SM)
    communication_oport::Int
    communication_iport::Int
end

const SHM_STATE = ShmState(Int32(-1), Int32(-1), Ptr{Cchar}(0), Ptr{Cchar}(0), 0, 0)

# System V SHM constants (Linux ABI)
const IPC_CREAT  = 0o1000
const IPC_RMID   = 0
const SHM_SIZE   = 256        # matches C++: shmget(key, 256, ...)

"""
    ConcoreState

Module-level mutable state, mirroring all the global variables used in
`concore.py` and the member fields of the C++ `Concore` class.
"""
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
