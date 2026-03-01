include("concore.jl")
using .ConcoreModule

# Define the pm function
function pm(u)
    return u .+ 0.01
end

# --- SETUP ---
# Instantiate Concore struct with desired parameters
c = Concore(delay=0.02, inpath="./in", outpath="./out")

maxtime = default_maxtime!(c, 150.0)

init_simtime_u  = "[0.0, 0.0]"
init_simtime_ym = "[0.0, 0.0]"

# Initialize ym from the init string
ym = ConcoreModule.safe_parse(init_simtime_ym, [0.0, 0.0])

# --- MAIN LOOP ---
while c.simtime < maxtime
    local u

    # unchanged(c) returns true when inputs have not changed
    while unchanged(c)
        # read_state!(c, port, name, initstr)
        u = read_state!(c, 1, "u", init_simtime_u)
    end

    #####
    global ym = pm(u)
    #####

    println("$(c.simtime). u=$(u) ym=$(ym)")

    # write_state!(c, port, name, val, delta)
    write_state!(c, 1, "ym", ym, 1.0)
end

println("retry=$(c.retrycount)")