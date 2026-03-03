"""
concore_file.py
===============
File-based transport layer for Concore, plus shared helpers used by both
the file and ZMQ paths.

Provides:
  - convert_numpy_to_python  — NumPy scalar → native Python type converter.
  - safe_literal_eval        — reads a file safely and evals its content.
  - parse_params / load_params — parameter-file parsing.
  - last_read_status         — module-level status string updated by read().
  - unchanged                — detects whether the simulation string changed.
  - read  / write / initval  — unified I/O that dispatches to ZMQ or file.

The ZMQ cases are delegated to concore_zmq.read_zmq / write_zmq so that
this file stays import-friendly even if pyzmq is unavailable (the import
error is deferred until a ZMQ port is actually used).
"""

import time
import logging
import os
from ast import literal_eval
import numpy as np

# Import ZMQ helpers; we import the module so the lazy-context logic and the
# shared _zmq_context live in one canonical place.
from ConcorePython import concore_zmq

logger = logging.getLogger('concore')

# ---------------------------------------------------------------------------
# NumPy Type Conversion Helper
# ---------------------------------------------------------------------------

def convert_numpy_to_python(obj):
    """Recursively convert numpy types to native Python types.

    This is necessary because literal_eval cannot parse numpy representations
    like np.float64(1.0), but can parse native Python types like 1.0.
    """
    if isinstance(obj, np.generic):
        return obj.item()
    elif isinstance(obj, list):
        return [convert_numpy_to_python(item) for item in obj]
    elif isinstance(obj, tuple):
        return tuple(convert_numpy_to_python(item) for item in obj)
    elif isinstance(obj, dict):
        return {key: convert_numpy_to_python(value) for key, value in obj.items()}
    else:
        return obj


# ---------------------------------------------------------------------------
# File & Parameter Handling
# ---------------------------------------------------------------------------

def safe_literal_eval(filename, defaultValue):
    """Read *filename* and return its evaluated content, or *defaultValue* on any error."""
    try:
        with open(filename, "r") as file:
            return literal_eval(file.read())
    except (FileNotFoundError, SyntaxError, ValueError, Exception):
        return defaultValue


# 9/21/22
# ---------------------------------------------------------------------------
# Parameter Parsing
# ---------------------------------------------------------------------------

def parse_params(sparams):
    """Parse a semicolon-separated key=value string (or a dict literal) into a dict."""
    params = {}
    if not sparams:
        return params

    s = sparams.strip()

    # Full dict literal
    if s.startswith("{") and s.endswith("}"):
        try:
            val = literal_eval(s)
            if isinstance(val, dict):
                return val
        except (ValueError, SyntaxError):
            pass

    for item in s.split(";"):
        if "=" in item:
            key, value = item.split("=", 1)  # split only once
            key = key.strip()
            value = value.strip()
            # Try to convert to Python type (int, float, list, etc.)
            # Use literal_eval to preserve backward compatibility (integers/lists)
            # Fall back to string for unquoted values (paths, URLs)
            try:
                params[key] = literal_eval(value)
            except (ValueError, SyntaxError):
                params[key] = value
    return params


def load_params(params_file):
    """Load and parse the params file.  Returns an empty dict on any error."""
    try:
        if os.path.exists(params_file):
            with open(params_file, "r") as f:
                sparams = f.read().strip()
            if sparams:
                # Windows sometimes keeps surrounding quotes
                if sparams[0] == '"' and sparams[-1] == '"':
                    sparams = sparams[1:-1]
                logger.debug("parsing sparams: " + sparams)
                p = parse_params(sparams)
                logger.debug("parsed params: " + str(p))
                return p
        return dict()
    except Exception:
        return dict()


# ---------------------------------------------------------------------------
# Read Status Tracking
# ---------------------------------------------------------------------------

last_read_status = "SUCCESS"


# ---------------------------------------------------------------------------
# I/O Helpers
# ---------------------------------------------------------------------------

def unchanged(mod):
    """Check if global string `s` is unchanged since last call."""
    if mod.olds == mod.s:
        mod.s = ''
        return True
    mod.olds = mod.s
    return False


# ---------------------------------------------------------------------------
# Unified read
# ---------------------------------------------------------------------------

def read(mod, port_identifier, name, initstr_val):
    """Read data from a ZMQ port or file-based port.

    Returns:
        tuple: (data, success_flag) where success_flag is True if real
            data was received, False if a fallback/default was used.
            Also sets ``concore_file.last_read_status`` (and the caller's
            ``last_read_status``) to one of:
            SUCCESS, FILE_NOT_FOUND, TIMEOUT, PARSE_ERROR,
            EMPTY_DATA, RETRIES_EXCEEDED.

    Backward compatibility:
        Legacy callers that do ``value = concore.read(...)`` will
        receive a tuple.  They can adapt with::

            result = concore.read(...)
            if isinstance(result, tuple):
                value, ok = result
            else:
                value, ok = result, True

        Alternatively, check ``concore.last_read_status`` after the call.
    """
    global last_read_status

    # Resolve the default / initial return value
    default_return_val = initstr_val
    if isinstance(initstr_val, str):
        try:
            default_return_val = literal_eval(initstr_val)
        except (SyntaxError, ValueError):
            pass

    # ------------------------------------------------------------------
    # Case 1: ZMQ port
    # ------------------------------------------------------------------
    if isinstance(port_identifier, str) and port_identifier in mod.zmq_ports:
        value, ok, status = concore_zmq.read_zmq(mod, port_identifier, default_return_val, last_read_status)
        last_read_status = status
        return value, ok

    # ------------------------------------------------------------------
    # Case 2: File-based port
    # ------------------------------------------------------------------
    try:
        file_port_num = int(port_identifier)
    except ValueError:
        logger.error(
            f"Error: Invalid port identifier '{port_identifier}' for file operation. "
            "Must be integer or ZMQ name."
        )
        last_read_status = "PARSE_ERROR"
        return default_return_val, False

    time.sleep(mod.delay)
    port_dir = mod._port_path(mod.inpath, file_port_num)
    file_path = os.path.join(port_dir, name)
    ins = ""

    file_not_found = False
    try:
        with open(file_path, "r") as infile:
            ins = infile.read()
    except FileNotFoundError:
        file_not_found = True
        ins = str(initstr_val)
        mod.s += ins  # Update s to break unchanged() loop
    except Exception as e:
        logger.error(f"Error reading {file_path}: {e}. Using default value.")
        last_read_status = "FILE_NOT_FOUND"
        return default_return_val, False

    # Retry logic if file is empty
    attempts = 0
    max_retries = 5
    while len(ins) == 0 and attempts < max_retries:
        time.sleep(mod.delay)
        try:
            with open(file_path, "r") as infile:
                ins = infile.read()
        except Exception as e:
            logger.warning(f"Retry {attempts + 1}: Error reading {file_path} - {e}")
        attempts += 1
        mod.retrycount += 1

    if len(ins) == 0:
        logger.error(f"Max retries reached for {file_path}, using default value.")
        last_read_status = "RETRIES_EXCEEDED"
        return default_return_val, False

    mod.s += ins

    # Try parsing
    try:
        inval = literal_eval(ins)
        if isinstance(inval, list) and len(inval) > 0:
            current_simtime_from_file = inval[0]
            if isinstance(current_simtime_from_file, (int, float)):
                mod.simtime = max(mod.simtime, current_simtime_from_file)
            if file_not_found:
                last_read_status = "FILE_NOT_FOUND"
                return inval[1:], False
            last_read_status = "SUCCESS"
            return inval[1:], True
        else:
            logger.warning(
                f"Warning: Unexpected data format in {file_path}: {ins}. "
                "Returning raw content or default."
            )
            if file_not_found:
                last_read_status = "FILE_NOT_FOUND"
                return inval, False
            last_read_status = "SUCCESS"
            return inval, True
    except Exception as e:
        logger.error(f"Error parsing content from {file_path} ('{ins}'): {e}. Returning default.")
        if file_not_found:
            last_read_status = "FILE_NOT_FOUND"
        else:
            last_read_status = "PARSE_ERROR"
        return default_return_val, False


# ---------------------------------------------------------------------------
# Unified write
# ---------------------------------------------------------------------------

def write(mod, port_identifier, name, val, delta=0):
    """
    Write data either to ZMQ port or file.
    `val` is the data payload (list or string); write() prepends [simtime + delta] internally.
    """
    # ------------------------------------------------------------------
    # Case 1: ZMQ port
    # ------------------------------------------------------------------
    if isinstance(port_identifier, str) and port_identifier in mod.zmq_ports:
        concore_zmq.write_zmq(mod, port_identifier, name, val, delta, convert_numpy_to_python)
        return

    # ------------------------------------------------------------------
    # Case 2: File-based port
    # ------------------------------------------------------------------
    try:
        file_port_num = int(port_identifier)
        port_dir = mod._port_path(mod.outpath, file_port_num)
        file_path = os.path.join(port_dir, name)
    except ValueError:
        logger.error(
            f"Error: Invalid port identifier '{port_identifier}' for file operation. "
            "Must be integer or ZMQ name."
        )
        return

    # File writing rules
    if isinstance(val, str):
        time.sleep(2 * mod.delay)  # string writes wait longer
    elif not isinstance(val, list):
        logger.error(f"File write to {file_path} must have list or str value, got {type(val)}")
        return

    try:
        with open(file_path, "w") as outfile:
            if isinstance(val, list):
                val_converted = convert_numpy_to_python(val)
                data_to_write = [mod.simtime + delta] + val_converted
                outfile.write(str(data_to_write))
                # simtime must not be mutated here.
                # Mutation breaks cross-language determinism (see issue #385).
            else:
                outfile.write(val)
    except Exception as e:
        logger.error(f"Error writing to {file_path}: {e}")


# ---------------------------------------------------------------------------
# initval
# ---------------------------------------------------------------------------

def initval(mod, simtime_val_str):
    """
    Initialize simtime from string containing a list.
    Example: "[10, 'foo', 'bar']" -> simtime=10, returns ['foo','bar']
    """
    try:
        val = literal_eval(simtime_val_str)
        if isinstance(val, list) and len(val) > 0:
            first_element = val[0]
            if isinstance(first_element, (int, float)):
                mod.simtime = first_element
                return val[1:]
            else:
                logger.error(
                    f"Error: First element in initval string '{simtime_val_str}' "
                    "is not a number. Using data part as is or empty."
                )
                return val[1:] if len(val) > 1 else []
        else:
            logger.error(
                f"Error: initval string '{simtime_val_str}' is not a list or is empty. "
                "Returning empty list."
            )
            return []
    except Exception as e:
        logger.error(f"Error parsing simtime_val_str '{simtime_val_str}': {e}. Returning empty list.")
        return []
