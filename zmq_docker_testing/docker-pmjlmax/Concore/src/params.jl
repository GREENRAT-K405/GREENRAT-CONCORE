# Safe parsing — replaces dangerous eval() with a strict JSON-based parser.
# Converts Python-style literals to valid JSON before parsing.

"""
    safe_parse(val_str, default_val)

Parse `val_str` as JSON (handling Python-style quotes and booleans).
Returns `default_val` on any failure. Never calls `eval`.
"""
function safe_parse(val_str::AbstractString, default_val)
    clean_str = replace(val_str, "'" => "\"")
    clean_str = replace(clean_str, "True" => "true")
    clean_str = replace(clean_str, "False" => "false")
    clean_str = replace(clean_str, "None" => "null")
    try
        return JSON.parse(clean_str)
    catch
        return default_val
    end
end

"""
    safe_literal_eval(filename, default_val)

Read `filename` and parse it with `safe_parse`. Returns `default_val` if missing.
"""
function safe_literal_eval(filename::String, default_val)
    try
        return safe_parse(Base.read(filename, String), default_val)
    catch
        return default_val
    end
end

"""
    parse_params(sparams) -> Dict

Parse a concore parameter string. Accepts either a JSON dict `{"k": v}`
or a semicolon-separated `k1=v1; k2=v2` list.
"""
function parse_params(sparams::String)::Dict{String, Any}
    params = Dict{String, Any}()
    s = strip(sparams)
    if isempty(s) return params end

    if startswith(s, "{") && endswith(s, "}")
        val = safe_parse(s, nothing)
        if val isa Dict return val end
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

Read `concore.params` and populate `state.params`. Called once on module load.
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

Return parameter `name` from `state.params`, or `default` if absent.
Mirrors Python's `concore.tryparam`.
"""
function tryparam(n::String, i)
    return get(state.params, n, i)
end

"""
    default_maxtime(default) -> Float64

Read `concore.maxtime` and store it in `state.maxtime`. Falls back to `default`.
"""
function default_maxtime(default)
    maxtime_file = joinpath(state.inpath * "1", "concore.maxtime")
    state.maxtime = Float64(safe_literal_eval(maxtime_file, default))
    return state.maxtime
end
