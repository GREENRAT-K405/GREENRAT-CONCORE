"""
concore_zmq.py
==============
ZeroMQ transport layer for Concore.

Provides:
  - A lazy-initialized shared ZMQ Context per process (_zmq_context / _get_zmq_context).
  - ZeroMQPort: thin wrapper around a single zmq socket (bind or connect).
  - init_zmq_port: registers a named ZMQ port on a module's zmq_ports dict.
  - terminate_zmq: cleanly closes all sockets and terminates the shared context.
  - read_zmq / write_zmq: the ZMQ-specific halves of the unified read/write API.

All public names are re-exported by ConcorePython/__init__.py so existing code
that does ``import concore_base`` (via the shim) continues to work unchanged.
"""

import time
import logging
import zmq

logger = logging.getLogger('concore')

# ---------------------------------------------------------------------------
# Shared ZMQ context (lazy-init)
# ---------------------------------------------------------------------------

# Lazy-initialised once per process.  File-only workflows never trigger ZMQ
# I/O threads at import time.
_zmq_context = None


def _get_zmq_context():
    """Return the process-level shared ZMQ context, creating it on first call."""
    global _zmq_context
    if _zmq_context is None or _zmq_context.closed:
        _zmq_context = zmq.Context()
    return _zmq_context


# ---------------------------------------------------------------------------
# ZeroMQPort
# ---------------------------------------------------------------------------

class ZeroMQPort:
    def __init__(self, port_type, address, zmq_socket_type, context=None):
        """
        port_type: "bind" or "connect"
        address: ZeroMQ address (e.g., "tcp://*:5555")
        zmq_socket_type: zmq.REQ, zmq.REP, zmq.PUB, zmq.SUB etc.
        context: optional zmq.Context() for the process; defaults to the shared _zmq_context.
        """
        if context is None:
            context = _get_zmq_context()
        self.socket = context.socket(zmq_socket_type)
        self.port_type = port_type  # "bind" or "connect"
        self.address = address

        # Configure timeouts & immediate close on failure
        self.socket.setsockopt(zmq.RCVTIMEO, 2000)   # 2 sec receive timeout
        self.socket.setsockopt(zmq.SNDTIMEO, 2000)   # 2 sec send timeout
        self.socket.setsockopt(zmq.LINGER, 0)        # Drop pending messages on close

        # Bind or connect
        if self.port_type == "bind":
            self.socket.bind(address)
            logger.info(f"ZMQ Port bound to {address}")
        else:
            self.socket.connect(address)
            logger.info(f"ZMQ Port connected to {address}")

    def send_json_with_retry(self, message):
        """Send JSON message with retries if timeout occurs."""
        for attempt in range(5):
            try:
                self.socket.send_json(message)
                return
            except zmq.Again:
                logger.warning(f"Send timeout (attempt {attempt + 1}/5)")
                time.sleep(0.5)
        logger.error("Failed to send after retries.")
        return

    def recv_json_with_retry(self):
        """Receive JSON message with retries if timeout occurs."""
        for attempt in range(5):
            try:
                return self.socket.recv_json()
            except zmq.Again:
                logger.warning(f"Receive timeout (attempt {attempt + 1}/5)")
                time.sleep(0.5)
        logger.error("Failed to receive after retries.")
        return None


# ---------------------------------------------------------------------------
# Port registry helpers
# ---------------------------------------------------------------------------

def init_zmq_port(mod, port_name, port_type, address, socket_type_str):
    """
    Initializes and registers a ZeroMQ port.

    mod: calling module (has zmq_ports dict)
    port_name (str): A unique name for this ZMQ port.
    port_type (str): "bind" or "connect".
    address (str): The ZMQ address (e.g., "tcp://*:5555", "tcp://localhost:5555").
    socket_type_str (str): String representation of ZMQ socket type (e.g., "REQ", "REP", "PUB", "SUB").
    """
    if port_name in mod.zmq_ports:
        logger.info(f"ZMQ Port {port_name} already initialized.")
        return  # Avoid reinitialization

    try:
        # Map socket type string to actual ZMQ constant (e.g., zmq.REQ, zmq.REP)
        zmq_socket_type = getattr(zmq, socket_type_str.upper())
        mod.zmq_ports[port_name] = ZeroMQPort(port_type, address, zmq_socket_type, _get_zmq_context())
        logger.info(f"Initialized ZMQ port: {port_name} ({socket_type_str}) on {address}")
    except AttributeError:
        logger.error(f"Error: Invalid ZMQ socket type string '{socket_type_str}'.")
    except zmq.error.ZMQError as e:
        logger.error(f"Error initializing ZMQ port {port_name} on {address}: {e}")
    except Exception as e:
        logger.error(f"An unexpected error occurred during ZMQ port initialization for {port_name}: {e}")


def terminate_zmq(mod):
    """Clean up all ZMQ sockets, then terminate the shared context once."""
    global _zmq_context  # declared first — used both in the early-return guard and reset below
    if mod._cleanup_in_progress:
        return  # Already cleaning up, prevent reentrant calls

    if not mod.zmq_ports and (_zmq_context is None or _zmq_context.closed):
        return  # Nothing to clean up: no ports and no active context

    mod._cleanup_in_progress = True
    print("\nCleaning up ZMQ resources...")

    # all sockets must be closed before context.term() is called.
    for port_name, port in mod.zmq_ports.items():
        try:
            port.socket.close()
            print(f"Closed ZMQ port: {port_name}")
        except Exception as e:
            logger.error(f"Error while terminating ZMQ port {port.address}: {e}")
    mod.zmq_ports.clear()

    # terminate the single shared context exactly once, then reset so it
    # can be safely recreated if init_zmq_port is called again later.
    if _zmq_context is not None and not _zmq_context.closed:
        try:
            _zmq_context.term()
        except Exception as e:
            logger.error(f"Error while terminating shared ZMQ context: {e}")
        _zmq_context = None

    mod._cleanup_in_progress = False


# ---------------------------------------------------------------------------
# ZMQ-specific read / write (called by the unified API in concore_file.py)
# ---------------------------------------------------------------------------

def read_zmq(mod, port_identifier, default_return_val, last_read_status_ref):
    """
    Read one message from a ZMQ port.

    Returns (value, success, status_string).
    `last_read_status_ref` is ignored (kept for symmetry); callers use the
    returned status_string to update their own last_read_status.
    """
    zmq_p = mod.zmq_ports[port_identifier]
    try:
        message = zmq_p.recv_json_with_retry()
        if message is None:
            return default_return_val, False, "TIMEOUT"
        # Strip simtime prefix if present (mirrors file-based read behaviour)
        if isinstance(message, list) and len(message) > 0:
            first_element = message[0]
            if isinstance(first_element, (int, float)):
                mod.simtime = max(mod.simtime, first_element)
                return message[1:], True, "SUCCESS"
        return message, True, "SUCCESS"
    except zmq.error.ZMQError as e:
        logger.error(f"ZMQ read error on port {port_identifier}: {e}. Returning default.")
        return default_return_val, False, "TIMEOUT"
    except Exception as e:
        logger.error(f"Unexpected ZMQ read error on port {port_identifier}: {e}. Returning default.")
        return default_return_val, False, "PARSE_ERROR"


def write_zmq(mod, port_identifier, name, val, delta, convert_numpy_to_python):
    """
    Write *val* to a ZMQ port.

    `convert_numpy_to_python` is passed in to avoid a circular import
    (the helper lives in concore_file.py).
    """
    zmq_p = mod.zmq_ports[port_identifier]
    try:
        zmq_val = convert_numpy_to_python(val)
        if isinstance(zmq_val, list):
            payload = [mod.simtime + delta] + zmq_val
            zmq_p.send_json_with_retry(payload)
            # simtime must not be mutated here.
            # Mutation breaks cross-language determinism (see issue #385).
        else:
            zmq_p.send_json_with_retry(zmq_val)
    except zmq.error.ZMQError as e:
        logger.error(f"ZMQ write error on port {port_identifier} (name: {name}): {e}")
    except Exception as e:
        logger.error(f"Unexpected ZMQ write error on port {port_identifier} (name: {name}): {e}")
