"""
ConcorePython/__init__.py
=========================
Public API for the ConcorePython package.

Importing this package (or the old ``concore_base`` shim) gives access to
every name that was previously in ``concore_base.py``:

  from ConcorePython import (
      # ZMQ layer  (concore_zmq.py)
      ZeroMQPort, _get_zmq_context,
      init_zmq_port, terminate_zmq,
      # File / shared layer  (concore_file.py)
      convert_numpy_to_python,
      safe_literal_eval, parse_params, load_params,
      last_read_status,
      unchanged, read, write, initval,
  )

``concore.py`` imports from here directly. The ``concore_base.py`` shim
also re-imports from here so that any third-party code using
``import concore_base`` continues to work without modification.
"""

# --- ZMQ layer ---
from ConcorePython.concore_zmq import (
    _zmq_context,
    _get_zmq_context,
    ZeroMQPort,
    init_zmq_port,
    terminate_zmq,
)

# --- File / shared layer ---
from ConcorePython.concore_file import (
    convert_numpy_to_python,
    safe_literal_eval,
    parse_params,
    load_params,
    last_read_status,
    unchanged,
    read,
    write,
    initval,
)

__all__ = [
    # ZMQ
    "_zmq_context",
    "_get_zmq_context",
    "ZeroMQPort",
    "init_zmq_port",
    "terminate_zmq",
    # File / shared
    "convert_numpy_to_python",
    "safe_literal_eval",
    "parse_params",
    "load_params",
    "last_read_status",
    "unchanged",
    "read",
    "write",
    "initval",
]
