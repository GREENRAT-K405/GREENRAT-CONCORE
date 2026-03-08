# Shared Memory (Linux only) — mirrors concore.hpp using POSIX System V SHM via ccall.
#
# Architecture:
#   - Writer (oport): create_shared_memory(key) → shmget + shmat → sharedData_create
#   - Reader (iport): get_shared_memory(key)    → shmget + shmat → sharedData_get
#   - write_SM writes into sharedData_create; read_SM reads from sharedData_get.
#   - Cleanup on exit: shmdt + shmctl(IPC_RMID)

"""
    extract_numeric(str) -> Int

Returns the leading positive integer from `str`, or -1 if there isn't one.
Mirrors C++ `ExtractNumeric` — used to decide if a port key maps to SHM.
"""
function extract_numeric(str::String)::Int
    m = match(r"^(\d+)", str)
    m === nothing && return -1
    n = parse(Int, m.captures[1])
    n <= 0 && return -1
    return n
end

if Sys.islinux()
    # Read a null-terminated string from a raw C pointer, up to `maxlen` bytes.
    function _shm_read_string(ptr::Ptr{Cchar}, maxlen::Int)::String
        buf = UInt8[]
        for i in 0:(maxlen - 1)
            b = unsafe_load(Ptr{UInt8}(ptr + i))
            b == 0x00 && break
            push!(buf, b)
        end
        return String(buf)
    end

    """Create a 256-byte SHM segment and attach as writer. Mirrors `Concore::createSharedMemory`."""
    function create_shared_memory(key::Int)
        id = ccall(:shmget, Cint, (Cint, Csize_t, Cint),
                   Cint(key), Csize_t(SHM_SIZE), Cint(IPC_CREAT | 0o666))
        if id == -1
            @error "SHM: Failed to create segment (key=$key)."
            return
        end
        SHM_STATE.shmId_create = id
        ptr = ccall(:shmat, Ptr{Cchar}, (Cint, Ptr{Cvoid}, Cint), id, C_NULL, Cint(0))
        if ptr == Ptr{Cchar}(-1)
            @error "SHM: Failed to attach segment (key=$key)."
            SHM_STATE.sharedData_create = Ptr{Cchar}(0)
        else
            SHM_STATE.sharedData_create = ptr
        end
    end

    """Wait for the writer to create the SHM segment, then attach as reader. Up to 100 retries."""
    function get_shared_memory(key::Int)
        MAX_RETRY = 100
        id = Cint(-1)
        for retry in 1:MAX_RETRY
            id = ccall(:shmget, Cint, (Cint, Csize_t, Cint),
                       Cint(key), Csize_t(SHM_SIZE), Cint(0o666))
            id != Cint(-1) && break
            println("Shared memory does not exist. Waiting for writer...")
            sleep(1)
        end
        if id == Cint(-1)
            @error "SHM: Failed to get segment after $MAX_RETRY retries (key=$key)."
            return
        end
        SHM_STATE.shmId_get = id
        ptr = ccall(:shmat, Ptr{Cchar}, (Cint, Ptr{Cvoid}, Cint), id, C_NULL, Cint(0))
        if ptr == Ptr{Cchar}(-1)
            @error "SHM: Failed to attach segment (key=$key)."
            SHM_STATE.sharedData_get = Ptr{Cchar}(0)
        else
            SHM_STATE.sharedData_get = ptr
        end
    end

    """Detach and delete both SHM segments on process exit. Mirrors the C++ destructor."""
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

# Initialise SHM from iport/oport after load_ports!().
# Mirrors the constructor logic in concore.hpp:
#   if oport key is numeric → communication_oport=1, createSharedMemory(key)
#   if iport key is numeric → communication_iport=1, getSharedMemory(key)
function _init_shm_from_ports!()
    Sys.islinux() || return

    oport_number = -1
    if !isempty(state.oport)
        oport_number = extract_numeric(string(first(keys(state.oport))))
    end

    iport_number = -1
    if !isempty(state.iport)
        iport_number = extract_numeric(string(first(keys(state.iport))))
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

# SHM I/O — read_SM / write_SM (Linux only)
if Sys.islinux()
    """Read from the SHM iport segment. Falls back to `initstr_val` if segment is empty."""
    function concore_read_SM(port_id::Integer, name::String, initstr_val)
        default_return = initstr_val isa AbstractString ? safe_parse(initstr_val, initstr_val) : initstr_val
        sleep(state.delay)

        ins = ""
        try
            if SHM_STATE.shmId_get != Cint(-1) && SHM_STATE.sharedData_get != Ptr{Cchar}(0)
                ins = _shm_read_string(SHM_STATE.sharedData_get, SHM_SIZE)
                isempty(ins) && throw(ErrorException("SHM buffer empty"))
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

    """Write a vector into the SHM oport segment."""
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

    """Write a string into the SHM oport segment."""
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
