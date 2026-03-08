function safe_parse(val_str::AbstractString, default_val)
    s = replace(val_str, "'" => "\"")
    s = replace(s, "True" => "true")
    s = replace(s, "False" => "false")
    s = replace(s, "None" => "null")
    try return JSON.parse(s) catch; return default_val end
end

function safe_literal_eval(filename::String, default_val)
    try return safe_parse(Base.read(filename, String), default_val)
    catch; return default_val end
end

function parse_params(sparams::String)::Dict{String, Any}
    params = Dict{String, Any}()
    s = strip(sparams)
    isempty(s) && return params

    if startswith(s, "{") && endswith(s, "}")
        val = safe_parse(s, nothing)
        if val isa Dict return val end
    end

    for item in split(s, ";")
        if occursin("=", item)
            parts = split(item, "="; limit=2)
            params[strip(parts[1])] = safe_parse(strip(parts[2]), strip(parts[2]))
        end
    end
    return params
end

function load_params!()
    f = joinpath(state.inpath * "1", "concore.params")
    if isfile(f)
        sparams = strip(Base.read(f, String))
        if startswith(sparams, "\"") && endswith(sparams, "\"")
            sparams = sparams[2:end-1]
        end
        state.params = parse_params(sparams)
    end
end

tryparam(n::String, i) = get(state.params, n, i)

function default_maxtime(default)
    f = joinpath(state.inpath * "1", "concore.maxtime")
    state.maxtime = Float64(safe_literal_eval(f, default))
    return state.maxtime
end

