module ConcoreModule

using JSON  # Added for robust cross-language serialization

println("This is terminal for Julia node")

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

# Helper: Pre-process Python string representations to valid JSON
function python_to_json_string(str::String)
    # Python's str() outputs single quotes and capitalized booleans/nulls.
    # JSON requires double quotes, true, false, null.
    clean_str = replace(str, "'" => "\"")
    clean_str = replace(clean_str, "True" => "true")
    clean_str = replace(clean_str, "False" => "false")
    clean_str = replace(clean_str, "None" => "null")
    return clean_str
end

# Helper: Safely parses python-style dict strings from file
function parse_port_file(filename::String)
    if isfile(filename)
        try
            content = read(filename, String)
            clean_content = python_to_json_string(content)
            parsed = JSON.parse(clean_content)
            # Convert keys to String and values to Int to ensure Dict{String, Int}
            return Dict{String, Int}(string(k) => Int(v) for (k, v) in parsed)
        catch e
            println("Warning: Could not parse $filename. Returning empty Dict.")
        end
    end
    return Dict{String, Int}()
end

# Helper: Parses string arrays natively using JSON
function parse_array(str::String)
    if isempty(strip(str)) return [] end
    try
        clean_str = python_to_json_string(str)
        return JSON.parse(clean_str)
    catch e
        println("Warning: Failed to parse array string: $str")
        return []
    end
end

# --- Initialization Logic ---

if Sys.iswindows()
    open("concorekill.bat", "w") do fpid
        write(fpid, "taskkill /F /PID $(getpid())\n")
    end
end

# Try loading ports
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
            global maxtime = parse(Float64, strip(content))
        else
            global maxtime = default
        end
    catch
        global maxtime = default
    end
end

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
        # Cast simtime safely in case JSON parsed it as an Int
        global simtime = max(simtime, Float64(inval[1]))
        return inval[2:end]
    end
    
    return []
end

# Changed Vector{<:Real} to AbstractVector to allow mixed types and strings
function write_data!(port::Int, name::String, val::Union{String, AbstractVector}, delta::Real=0.0)
    global outpath, simtime, delay
    
    if isa(val, String)
        sleep(2 * delay)
    end

    filepath = joinpath(outpath * string(port), name)
    
    try
        open(filepath, "w") do outfile
            if isa(val, AbstractVector)
                # vcat safely merges the simtime with the rest of the array, regardless of types
                data_to_write = vcat([simtime + delta], val)
                # JSON.json outputs a string that Python's literal_eval can read natively
                write(outfile, JSON.json(data_to_write))
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
        global simtime = Float64(val[1])
        return val[2:end]
    end
    return []
end

end # module