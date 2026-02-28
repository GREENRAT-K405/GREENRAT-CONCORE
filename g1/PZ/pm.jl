include("concore.jl")
using .ConcoreModule

# Define the pm function
function pm(u)
    return u .+ 0.01
end

# --- SETUP ---
# No struct instantiation (c = Concore()) needed. 
# We interact directly with the module's global state.

# Configure simulation parameters
default_maxtime!(150.0)  # Call directly, no 'c' passed

# Access global variables via the module name
ConcoreModule.delay = 0.02 

init_simtime_u = "[0.0, 0.0]"
init_simtime_ym = "[0.0, 0.0]"

# Initialize ym. 
ym = initval!(init_simtime_ym) # No 'c' passed

# --- MAIN LOOP ---
# Check globals: ConcoreModule.simtime and ConcoreModule.maxtime
while ConcoreModule.simtime < ConcoreModule.maxtime
    local u 
    
    # unchanged! takes no arguments now
    while unchanged!()
        # read_data! takes (port, name, initstr) - no 'c'
        u = read_data!(1, "u", init_simtime_u)
    end
    
    #####
    global ym = pm(u)
    #####
    
    println("$(ConcoreModule.simtime). u=$(u) ym=$(ym)")
    
    # write_data! takes (port, name, val, delta) - no 'c'
    write_data!(1, "ym", ym, 1.0)
end

println("retry=$(ConcoreModule.retrycount)")