# ===================================================================
# Port Configuration (concore.iport / concore.oport)
# ===================================================================
# Mirrors Python: iport = safe_literal_eval("concore.iport", {})
#                 oport = safe_literal_eval("concore.oport", {})
# These files live in the component's working directory (not inpath).

"""
    load_ports!()

Read `concore.iport` and `concore.oport` from the working directory and
populate `state.iport` / `state.oport`. Called once on module load.
"""
function load_ports!()
    raw_iport = safe_literal_eval("concore.iport", Dict{String, Any}())
    raw_oport = safe_literal_eval("concore.oport", Dict{String, Any}())
    # safe_parse returns JSON-parsed types; normalise keys to String
    if raw_iport isa Dict
        state.iport = Dict{String, Any}(string(k) => v for (k, v) in raw_iport)
    end
    if raw_oport isa Dict
        state.oport = Dict{String, Any}(string(k) => v for (k, v) in raw_oport)
    end
end

"""
    iport() -> Dict{String, Any}

Return the current input-port map loaded from `concore.iport`.
"""
iport() = state.iport

"""
    oport() -> Dict{String, Any}

Return the current output-port map loaded from `concore.oport`.
"""
oport() = state.oport
