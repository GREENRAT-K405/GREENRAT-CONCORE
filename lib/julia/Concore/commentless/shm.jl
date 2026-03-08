function extract_numeric(str::String)::Int
    m = match(r"^(\d+)", str)
    m === nothing && return -1
    n = parse(Int, m.captures[1])
    return n <= 0 ? -1 : n
end

if Sys.islinux()
    function _shm_read_string(ptr::Ptr{Cchar}, maxlen::Int)::String
        buf = UInt8[]
        for i in 0:(maxlen - 1)
            b = unsafe_load(Ptr{UInt8}(ptr + i))
            b == 0x00 && break
            push!(buf, b)
        end
        return String(buf)
    end

    function create_shared_memory(key::Int)
        id = ccall(:shmget, Cint, (Cint, Csize_t, Cint),
                   Cint(key), Csize_t(SHM_SIZE), Cint(IPC_CREAT | 0o666))
        id == -1 && (@error "SHM: create failed (key=$key)."; return)
        SHM_STATE.shmId_create = id
        ptr = ccall(:shmat, Ptr{Cchar}, (Cint, Ptr{Cvoid}, Cint), id, C_NULL, Cint(0))
        SHM_STATE.sharedData_create = ptr == Ptr{Cchar}(-1) ? Ptr{Cchar}(0) : ptr
    end

    function get_shared_memory(key::Int)
        id = Cint(-1)
        for _ in 1:100
            id = ccall(:shmget, Cint, (Cint, Csize_t, Cint),
                       Cint(key), Csize_t(SHM_SIZE), Cint(0o666))
            id != Cint(-1) && break
            sleep(1)
        end
        id == Cint(-1) && (@error "SHM: get failed (key=$key)."; return)
        SHM_STATE.shmId_get = id
        ptr = ccall(:shmat, Ptr{Cchar}, (Cint, Ptr{Cvoid}, Cint), id, C_NULL, Cint(0))
        SHM_STATE.sharedData_get = ptr == Ptr{Cchar}(-1) ? Ptr{Cchar}(0) : ptr
    end

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
end

function _init_shm_from_ports!()
    Sys.islinux() || return
    oport_key = isempty(state.oport) ? -1 : extract_numeric(string(first(keys(state.oport))))
    iport_key = isempty(state.iport) ? -1 : extract_numeric(string(first(keys(state.iport))))
    if oport_key != -1; SHM_STATE.communication_oport = 1; create_shared_memory(oport_key) end
    if iport_key != -1; SHM_STATE.communication_iport = 1; get_shared_memory(iport_key) end
end

if Sys.islinux()
    function concore_read_SM(port_id::Integer, name::String, initstr_val)
        default_return = initstr_val isa AbstractString ? safe_parse(initstr_val, initstr_val) : initstr_val
        sleep(state.delay)
        ins = ""
        try
            ins = _shm_read_string(SHM_STATE.sharedData_get, SHM_SIZE)
            isempty(ins) && (ins = string(initstr_val))
        catch; ins = string(initstr_val) end

        for _ in 1:100
            !isempty(ins) && break
            sleep(state.delay)
            try ins = _shm_read_string(SHM_STATE.sharedData_get, SHM_SIZE) catch end
            state.retrycount += 1
        end

        state.s *= ins
        parsed = safe_parse(ins, default_return)
        if parsed isa AbstractVector && !isempty(parsed) && parsed[1] isa Number
            state.simtime = max(state.simtime, parsed[1])
            return parsed[2:end]
        end
        return parsed
    end

    function concore_write_SM(port_id::Integer, name::String, val::AbstractVector, delta::Real=0)
        payload = "[" * join(vcat([state.simtime + delta], val), ",") * "]"
        nbytes  = min(length(payload), SHM_SIZE - 1)
        unsafe_copyto!(SHM_STATE.sharedData_create,
                       pointer(Vector{Cchar}(codeunits(payload))), nbytes)
        unsafe_store!(SHM_STATE.sharedData_create + nbytes, Cchar(0))
    end

    function concore_write_SM(port_id::Integer, name::String, val::AbstractString, delta::Real=0)
        sleep(2 * state.delay)
        nbytes = min(length(val), SHM_SIZE - 1)
        unsafe_copyto!(SHM_STATE.sharedData_create,
                       pointer(Vector{Cchar}(codeunits(val))), nbytes)
        unsafe_store!(SHM_STATE.sharedData_create + nbytes, Cchar(0))
    end
end
