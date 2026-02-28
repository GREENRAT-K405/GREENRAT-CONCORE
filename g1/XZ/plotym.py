import concore
import numpy as np
import matplotlib.pyplot as plt
import time

print("plotym - Live Mode")

# Simulation Configuration
concore.delay = 0.02
concore.default_maxtime(150)
init_simtime_ym = "[0.0, 0.0]"
ym = concore.initval(init_simtime_ym) #

# Initialize Live Plot
plt.ion()  # Turn on interactive mode
fig, ax = plt.subplots()
line1, = ax.plot([], [], 'b-', label='ym')
ax.set_ylabel('ym')
ax.set_xlabel('Cycles')
ax.legend(loc='upper right')

# Data buffers for live plotting
x_data = []
ym1_data = []

# Ensure the plot window is visible before starting
plt.show()

try:
    while(concore.simtime < concore.maxtime): #
        while concore.unchanged(): #
            ym = concore.read(1, "ym", init_simtime_ym) #
        
        concore.write(1, "ym", ym) #
        print("ym=" + str(ym))
        
        # Update data buffers
        current_step = len(x_data)
        x_data.append(current_step)
        ym1_data.append(ym[0])
        
        # Update plot line data
        line1.set_data(x_data, ym1_data)
        
        # Adjust axes limits dynamically
        ax.relim()
        ax.autoscale_view()
        
        # Pause briefly to allow the GUI thread to refresh the window
        plt.pause(0.001)

except KeyboardInterrupt:
    print("\nSimulation interrupted by user.")

print("retry=" + str(concore.retrycount)) #

# Finalize plot
plt.ioff() # Turn off interactive mode
plt.savefig("ym_live_final.pdf")
plt.show() # Keep plot open after simulation ends