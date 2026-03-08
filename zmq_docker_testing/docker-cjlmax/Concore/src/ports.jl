# Port configuration — reads concore.iport / concore.oport from the working directory.

"""
    load_ports!()

Read `concore.iport` and `concore.oport` files and populate `state.iport` / `state.oport`.
"""
function load_ports!()
    raw_iport = safe_literal_eval("concore.iport", Dict{String, Any}())
    raw_oport = safe_literal_eval("concore.oport", Dict{String, Any}())
    if raw_iport isa Dict
        state.iport = Dict{String, Any}(string(k) => v for (k, v) in raw_iport)
    end
    if raw_oport isa Dict
        state.oport = Dict{String, Any}(string(k) => v for (k, v) in raw_oport)
    end
end

"""iport() -> Dict — return the loaded input-port map."""
iport() = state.iport

"""oport() -> Dict — return the loaded output-port map."""
oport() = state.oport
