    using Concore

# Define the pm function
function pm(u)
    return u .+ 0.01
end

# --- SETUP ---
# Configure the global Concore state
Concore.state.delay   = 0.02
Concore.state.inpath  = "./in"
Concore.state.outpath = "./out"

maxtime = default_maxtime(150.0)

init_simtime_u  = "[0.0, 0.0]"
init_simtime_ym = "[0.0, 0.0]"

# Initialize ym from the init string
ym = Concore.safe_parse(init_simtime_ym, [0.0, 0.0])

# --- MAIN LOOP ---
while Concore.state.simtime < maxtime
    local u

    # unchanged() returns true when inputs have not changed
    while unchanged()
        # concore_read(port, name, initstr)
        u = Float64.(concore_read(1, "u", init_simtime_u))
    end

    #####
    global ym = pm(u)
    #####

    println("$(Concore.state.simtime). u=$(u) ym=$(ym)")

    # concore_write(port, name, val, delta)
    concore_write(1, "ym", ym, 1.0)
end

println("retry=$(Concore.state.retrycount)")