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
