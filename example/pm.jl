# Include the file containing your ConcoreModule (adjust the filename if needed)
include("concore.jl")
using .ConcoreModule

# Define the pm function
# Using the broadcast operator (.+) to handle array additions element-wise
function pm(u)
    return u .+ 0.01
end

# Initialize the Concore instance to hold the simulation state
c = Concore()

# Configure the simulation parameters
default_maxtime!(c, 150.0) 
c.delay = 0.02

init_simtime_u = "[0.0, 0.0]"
init_simtime_ym = "[0.0, 0.0]"

# Initialize ym. initval! returns a Vector{Float64} payload
ym = initval!(c, init_simtime_ym)

# Main simulation loop
while c.simtime < c.maxtime
    local u  # Declare u as local so it is accessible outside the inner while loop
    
    while unchanged!(c)
        u = read_data!(c, 1, "u", init_simtime_u)
    end
    
    #####
    ym = pm(u)
    #####
    
    println("$(c.simtime). u=$(u) ym=$(ym)")
    
    # Write the data. write_data! expects a Vector and handles the delta natively
    write_data!(c, 1, "ym", ym, 1.0)
end

println("retry=$(c.retrycount)")