module ConcoreModule

export read_data!, write_data!, unchanged!, initval!, default_maxtime!

# --- Global Variables (matching concore.py) ---
global s = ""
global olds = ""
global delay = 1.0
global retrycount = 0
global simtime = 0.0
global inpath = "./in"
global outpath = "./out"
global maxtime = 100.0  # Default, updated by default_maxtime!
global iport = Dict{String, Int}()
global oport = Dict{String, Int}()

# --- Helper Functions ---

# Helper: Safely parses python-style dict strings from file
function parse_port_file(filename::String)
    d = Dict{String, Int}()
    if isfile(filename)
        content = read(filename, String)
        # Regex to match key-value pairs ignoring quotes and spaces
        matches = eachmatch(r"['\"]([^'\"]+)['\"]\s*:\s*(\d+)", content)
        for m in matches
            d[m.captures[1]] = parse(Int, m.captures[2])
        end
    end
    return d
end

# Helper: Parses string arrays: "[1.0, 2.5]" -> Vector{Float64}
function parse_array(str::String)
    clean_str = strip(str, ['[', ']', ' ', '\n', '\r'])
    if isempty(clean_str) return Float64[] end
    parts = split(clean_str, ',')
    parts = filter(!isempty, parts)
    return parse.(Float64, parts)
end

# --- Initialization Logic ---

# Python: if hasattr(sys, 'getwindowsversion')...
if Sys.iswindows()
    open("concorekill.bat", "w") do fpid
        write(fpid, "taskkill /F /PID $(getpid())\n")
    end
end

# Python: try loading ports
try
    global iport = parse_port_file("concore.iport")
catch
    global iport = Dict{String, Int}()
end

try
    global oport = parse_port_file("concore.oport")
catch
    global oport = Dict{String, Int}()
end

# --- Core Functions ---

function default_maxtime!(default::Float64=100.0)
    global maxtime, inpath
    filepath = joinpath(inpath * "1", "concore.maxtime")
    try
        if isfile(filepath)
            content = read(filepath, String)
            # Assuming file contains a scalar number
            global maxtime = parse(Float64, strip(content))
        else
            global maxtime = default
        end
    catch
        global maxtime = default
    end
end

# Initialize maxtime immediately (like Python script execution)
default_maxtime!(100.0)

function unchanged!()
    global s, olds
    if olds == s
        global s = ""
        return true
    else
        global olds = s
        return false
    end
end

function read_data!(port::Int, name::String, initstr::String)
    global s, simtime, retrycount, delay, inpath
    
    sleep(delay)
    filepath = joinpath(inpath * string(port), name)
    ins = ""
    
    try
        ins = isfile(filepath) ? read(filepath, String) : initstr
    catch
        ins = initstr
    end

    while isempty(ins)
        sleep(delay)
        try
            ins = read(filepath, String)
        catch
            ins = ""
        end
        global retrycount += 1
    end

    global s *= ins
    inval = parse_array(ins)
    
    if length(inval) > 0
        # Python: simtime = max(simtime, inval[0])
        global simtime = max(simtime, inval[1])
        return inval[2:end]
    end
    
    return Float64[]
end

function write_data!(port::Int, name::String, val::Union{String, Vector{<:Real}}, delta::Real=0.0)
    global outpath, simtime, delay
    
    if isa(val, String)
        sleep(2 * delay)
    elseif !isa(val, Vector)
        println("write_data! must have Vector or String")
        exit() 
    end

    filepath = joinpath(outpath * string(port), name)
    
    try
        open(filepath, "w") do outfile
            if isa(val, Vector)
                # data_to_write = [simtime + delta] + val
                data_to_write = vcat([simtime + delta], Float64.(val))
                # Write in Python list format: [x, y, z]
                write(outfile, "[" * join(data_to_write, ", ") * "]")
                global simtime += delta
            else
                write(outfile, val)
            end
        end
    catch
        println("skipping " * filepath)
    end
end

function initval!(simtime_val::String)
    global simtime
    val = parse_array(simtime_val)
    if length(val) > 0
        global simtime = val[1]
        return val[2:end]
    end
    return Float64[]
end

end # module