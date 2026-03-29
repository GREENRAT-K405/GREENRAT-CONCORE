# Concore Julia Frontend — Prototype for GSoC 2026

Welcome to my Julia implementation of Concore, which I have developed as a functional prototype for my Google Summer of Code (GSoC) 2026 project. My goal here is to introduce a fast, robust, and secure frontend that enables high-performance co-simulation node integrations natively in Julia.

## 🌟 Why I Built This Prototype

I designed this Julia port from the ground up to address several limitations I identified in the classic Python and C++ implementations. By leveraging Julia's unique strengths, such as Multiple Dispatch and seamless C-Interop (`ccall`), I've improved the system's performance, safety, and maintainability.

- **Three Transport Backends:** I implemented full support for:
  - **File Method (FM):** Shared filesystem I/O with automatic backoff and retry, ensuring it works universally.
  - **System V Shared Memory (SM):** Ultra-fast POSIX Shared Memory exclusively for Linux using native `ccall`.
  - **ZeroMQ (ZMQ):** Socket-based robust messaging for distributed and Dockerized nodes.
- **Multiple Dispatch:** I utilized Julia's multiple dispatch to unify the `concore_read` and `concore_write` methods. They now route naturally based on the `port_id` type (`String` for ZMQ, `Integer` for FM/SM). This completely eliminated the convoluted `if/else` routing chains found in the legacy codebase!
- **Security-First Parsing:** I realized that the legacy Python implementations relied on the dangerous `eval()` function to parse configurations. I completely eliminated this by writing a custom `safe_parse` function, which uses string replacements and `JSON.parse` to evaluate Python-centric configuration payloads safely.
- **Docker-Native Execution:** I built a dynamically swapped runtime execution (`concoredocker.jl`) tailored for Docker containers, using absolute volume mounts (`/in`, `/out`), format-friendly stdio loggers, and automatic `SIGTERM` handlers.

---

## 📂 Architecture & File Structure

I partitioned the implementation logic within `lib/julia/Concore/src/` to ensure modularity. Here is how I structured it:

- **Execution Entrypoints:**
  - `Concore.jl`: The main module I use for standard local execution.
  - `concoredocker.jl`: I designed this to be swapped in by `mkconcore.py` when building Docker images to handle container-specific pathing and logging.
  - `concore_base.jl`: Core includes and exports that I share between both entrypoints.
- **Core Systems:**
  - `io.jl`: My public API providing multi-dispatched `concore_read`, `concore_write`, `initval`, and `unchanged`.
  - `shm.jl`: I mapped this directly to the `concore.hpp` C++ logic. It creates and attaches to 256-byte IPC segments natively using Linux `shmget`, `shmat`, `shmdt`, and `shmctl`. 
  - `zmq.jl`: My ZeroMQ transport layer, including socket lifecycle management, Windows/Linux context-specific setups, and `atexit` tear-down routines.
  - `state.jl`: I replaced the scattered global variables with strong, typed, unified structures (`ConcoreState`, `ShmState`, `ZeroMQPort`).
  - `params.jl`: Parameter configuration utilities and my safe JSON-based parser payload injection.
  - `ports.jl`: Configuration maps parser module (`concore.iport`, `concore.oport`).

---

## 🛠️ Public API 

Here is how I designed the API to be used:

### Port Initialization
```julia
# Initialize a ZeroMQ socket (e.g. REP, REQ, PUB, SUB)
init_zmq_port(port_name::String, port_type::String, address::String, socket_type::String)

# ZMQ termination happens automatically on exit, but I added this so it can be forced manually
terminate_zmq()
```

### I/O Operations
```julia
# Reads from ZMQ (since port_id is a String)
data = concore_read("U3", "u_signal", "[0.0, 1.0]")

# Reads from File/SHM (since port_id is an Integer)
data = concore_read(1, "u_signal", "[0.0, 1.0]")

# Writes a vector over ZMQ
concore_write("U3", "ym_signal", [1.0, 2.5])

# Checks if state has changed since last read
if !unchanged()
    println("New data arrived!")
end

# Parses an initstr and correctly sets simulation time state
initval("[0.1, 5.0, 3.0]")
```

### Configuration
```julia
# Access safely parsed parameters from `concore.params`
val = tryparam("model_name", "default_model")

# Port lookup maps
dict_in = iport()
dict_out = oport()
```

---

## 🚀 Examples

To prove the prototype works, I wrote the following examples:

### 1. ZMQ Server Benchmarking Node
I designed this node to benchmark network transmission throughput.

```julia
import Concore

Concore.init_zmq_port("throughput_port", "connect", "tcp://127.0.0.1:5555", "REQ")
message_count = 0

while time() < end_time
    Concore.concore_write("throughput_port", "throughput_test", Dict("ping" => "hello"))
    reply = Concore.concore_read("throughput_port", "throughput_reply", "{}")
    if !isempty(reply)
        message_count += 1
    end
end
Concore.terminate_zmq()
```

### 2. Multi-Transport Relay Server
I built this node to act as a bridge. It connects ZMQ based inputs to local File/SHM based components, seamlessly adapting between transports.

```julia
import Concore: init_zmq_port, concore_read, concore_write, unchanged, state

init_zmq_port("ZMQ_IN", "bind", "tcp://*:4660", "REP")
state.maxtime = 100.0

while state.simtime < state.maxtime
    # 1. Read input over ZMQ network
    u_data = concore_read("ZMQ_IN", "u_signal", "[0.0, 0.0]")
    
    # 2. Relay directly to a local file method (FM/SM) simulator over port `U2`
    if haskey(state.oport, "U2")
        concore_write(state.oport["U2"], "u", u_data)
    end
    
    # 3. Block and wait for local Simulator step simulation via port `Y2`
    old_time = state.simtime
    while unchanged() || state.simtime <= old_time
        y_data = concore_read(state.iport["vol_Y2"], "ym", "[0.0, 0.0]")
    end
    
    # 4. Reply with results over ZMQ network
    concore_write("ZMQ_IN", "ym_signal", y_data)
end
```

---

## 🔒 Security Enhancements
When reviewing the legacy Concore implementations (e.g., the Python scripts), I noticed they commonly parsed properties file payloads using the built-in `eval()` function. In distributed environments, this trivially exposes the node host to arbitrary code execution if the string is intercepted or maliciously modified.

To fix this major security flaw, I entirely avoided `eval()` in this Julia library by building a `safe_parse()` function. It sanitizes payloads (e.g., translating Python-specific `True`/`False` booleans to standard JSON `true`/`false`, single-quotes into standard double-quotes, and `None` to `null`) and strictly processes configuration structures with `JSON.parse`. As a result, command injection execution vectors via properties injection are neutralized in my prototype!

## 🐳 Docker Deployment Magic
To ensure my prototype handles containerization gracefully, I integrated it with the deployment utility (`mkconcore.py`). When containerizing a node, my script swaps the module definition from `Concore.jl` strictly into `concoredocker.jl`. With this, the container runtime benefits from:
1. **Implicit adaptation** to absolute filesystem paths bounding standard Docker container volumes (`/in`, `/out`).
2. **Standardized logging**, where multiline formats are natively flattened into concise stream indicators easily interpreted by standard `docker logs` commands. 
3. **Explicit `SIGTERM` trap bindings**, guaranteeing that standard execution shutdowns (like `docker stop`) clean ZMQ dangling descriptors effortlessly rather than leaving lingering open socket ports.
