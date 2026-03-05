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
