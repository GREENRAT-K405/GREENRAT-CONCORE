import time
import os
from ast import literal_eval
import sys
import numpy as np # Added for numpy type conversion

#if windows, create script to kill this process 
# because batch files don't provide easy way to know pid of last command
# ignored for posix!=windows, because "concorepid" is handled by script
# ignored for docker (linux!=windows), because handled by docker stop
if hasattr(sys, 'getwindowsversion'):
    with open("concorekill.bat","w") as fpid:
        fpid.write("taskkill /F /PID "+str(os.getpid())+"\n")

# NumPy Type Conversion Helper
def convert_numpy_to_python(obj):
    #Recursively convert numpy types to native Python types.
    #This is necessary because literal_eval cannot parse numpy representations
    #like np.float64(1.0), but can parse native Python types like 1.0.
    if isinstance(obj, np.generic):
        # Convert numpy scalar types to Python native types
        return obj.item()
    elif isinstance(obj, list):
        return [convert_numpy_to_python(item) for item in obj]
    elif isinstance(obj, tuple):
        return tuple(convert_numpy_to_python(item) for item in obj)
    elif isinstance(obj, dict):
        return {key: convert_numpy_to_python(value) for key, value in obj.items()}
    else:
        return obj


try:
    iport = literal_eval(open("concore.iport").read())
except:
    iport = dict()
try:
    oport = literal_eval(open("concore.oport").read())
except:
    oport = dict()



s = ''
olds = ''
delay = 1
retrycount = 0
inpath = "./in" #must be rel path for local
outpath = "./out"

#9/12/21
def default_maxtime(default):
    global maxtime
    try:
        maxtime = literal_eval(open(inpath+"1/concore.maxtime").read())
    except:
        maxtime = default 
default_maxtime(100)

def unchanged():
    global olds,s
    if olds==s:
        s = ''
        return True
    else:       
        olds = s       
        return False

def read(port, name, initstr):
    global s,simtime,retrycount
    time.sleep(delay)
    try:
        infile = open(inpath+str(port)+"/"+name);
        ins = infile.read()
    except:
        ins = initstr
    while len(ins)==0:
        time.sleep(delay)
        ins = infile.read()
        retrycount += 1
    s += ins
    inval = literal_eval(ins)
    simtime = max(simtime,inval[0])
    return inval[1:]

def write(port, name, val, delta=0):
    global outpath,simtime
    if isinstance(val,str):
        time.sleep(2*delay)
    elif isinstance(val,list)==False:
        print("mywrite must have list or str")
        quit() 
    try:
        with open(outpath+str(port)+"/"+name,"w") as outfile:     
            if isinstance(val,list):
                val_converted = convert_numpy_to_python(val)
                data_to_write = [simtime + delta] + val_converted
                outfile.write(str(data_to_write))
                simtime += delta 
            else:
                outfile.write(val)
    except:
        print("skipping"+outpath+str(port)+"/"+name);

def initval(simtime_val):
    global simtime
    val = literal_eval(simtime_val)
    simtime = val[0]
    return val[1:]

