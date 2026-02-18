module ConcoreModule

export Concore, read_data!, write_data!, unchanged!, initval!, default_maxtime!

mutable struct Concore
    s::String
    olds::String
    delay::Float64   # Fixed typo here
    retrycount::Int
    simtime::Float64
    inpath::String
    outpath::String
    iport::Dict{String, Int}
    oport::Dict{String, Int}
    maxtime::Float64

    function Concore()
        iport = parse_port_file("concore.iport")
        oport = parse_port_file("concore.oport")
        new("", "", 1.0, 0, 0.0, "./in", "./out", iport, oport, 100.0)
    end
end

# Helper: Safely parses python-style dict strings: {'portA': 1, 'portB': 2}
function parse_port_file(filename::String)
    dict = Dict{String, Int}()
    if isfile(filename)
        content = read(filename, String)
        # Regex to match key-value pairs ignoring quotes and spaces
        matches = eachmatch(r"['\"]([^'\"]+)['\"]\s*:\s*(\d+)", content)
        for m in matches
            dict[m.captures[1]] = parse(Int, m.captures[2])
        end
    end
    return dict
end

# Helper: Parses string arrays: "[1.0, 2.5, 3.1]" -> Vector{Float64}
function parse_array(str::String)
    clean_str = strip(str, ['[', ']', ' ', '\n', '\r'])
    if isempty(clean_str) return Float64[] end
    parts = split(clean_str, ',')
    return parse.(Float64, parts)
end

function default_maxtime!(c::Concore, default::Float64=100.0)
    filepath = joinpath(c.inpath * "1", "concore.maxtime")
    if isfile(filepath)
        try
            c.maxtime = parse(Float64, read(filepath, String))
        catch
            c.maxtime = default
        end
    else
        c.maxtime = default
    end
end

function unchanged!(c::Concore)
    if c.olds == c.s
        c.s = ""
        return true
    else
        c.olds = c.s
        return false
    end
end

function read_data!(c::Concore, port::Int, name::String, initstr::String)
    sleep(c.delay)
    filepath = joinpath(c.inpath * string(port), name)
    ins = ""
    
    try
        ins = isfile(filepath) ? read(filepath, String) : initstr
    catch
        ins = initstr
    end

    while isempty(ins)  # Idiomatic check
        sleep(c.delay)
        try
            ins = read(filepath, String)
        catch
            ins = "" # Explicitly reset on read failure to maintain the loop
        end
        c.retrycount += 1
    end

    c.s *= ins
    inval = parse_array(ins)
    
    if length(inval) > 0
        c.simtime = max(c.simtime, inval[1])
        return inval[2:end] # Return payload excluding simtime
    end
    
    return Float64[]
end

function write_data!(c::Concore, port::Int, name::String, val::Union{String, Vector{<:Real}}, delta::Real=0.0)
    if isa(val, String)
        sleep(2 * c.delay)
    end
    
    filepath = joinpath(c.outpath * string(port), name)
    
    try
        open(filepath, "w") do outfile
            if isa(val, Vector)
                # Prepend simtime + delta to the array
                data_to_write = vcat([c.simtime + delta], Float64.(val))
                # Write in the format [val1, val2, ...]
                write(outfile, "[" * join(data_to_write, ", ") * "]")
                c.simtime += delta
            else
                write(outfile, val)
            end
        end
    catch
        println("skipping $(filepath)")
    end
end

function initval!(c::Concore, simtime_val::String)
    val = parse_array(simtime_val)
    if length(val) > 0
        c.simtime = val[1]
        return val[2:end]
    end
    return Float64[]
end

end # module