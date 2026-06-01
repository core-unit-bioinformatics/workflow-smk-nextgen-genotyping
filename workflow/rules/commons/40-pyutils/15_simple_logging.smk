"""This module implements simple
'logging' type of functions to
write messages to standard streams.
As a rule of thumb for developers,
functions in this module should require
only minimal input (parameters), provide no
output and have only a well-defined side effect,
i.e. logging a message to a stream.
"""

import sys


_THIS_MODULE = ["commons", "40-pyutils", "15_simple_logging.smk"]
_THIS_CONTEXT = DocContext.TEMPLATE

DOCREC.add_module_doc(_THIS_CONTEXT, _THIS_MODULE)


def logerr(msg):
    """
    Log a message to sys.stderr.
    If VERBOSE is set, the level is
    set to 'VERBOSE (err/dbg)' and to
    'ERROR' otherwise. The message is
    prefixed with the current timestamp.

    Args:
        msg (str): message text

    Returns:
        None
    """
    level = "ERROR"
    if VERBOSE:
        level = "VERBOSE (err/dbg)"
    write_log_message(sys.stderr, level, msg)
    return


DOCREC.add_function_doc(logerr)


def log_err(msg):
    """
    Alias for 'loggerr'
    """
    _ = logerr(msg)
    return


DOCREC.add_function_doc(log_err)


def logout(msg):
    """
    Log a message to sys.stdout with level
    INFO. The message is prefixed with
    the current timestamp.

    Args:
        msg (str): message text

    Returns:
        None
    """
    write_log_message(sys.stdout, "INFO", msg)
    return


DOCREC.add_function_doc(logout)


def log_out(msg):
    """
    Alias for 'logout'
    """
    _ = logout(msg)
    return


DOCREC.add_function_doc(log_out)


def write_log_message(stream, level, message):
    """
    Log a message with info 'level' to 'stream',
    which must feature a write method. By default,
    the 'message' is prefixed with the current timestamp.

    TODO - introduce enum type for levels?
    Level should be informative such as ERROR,
    WARNING, DEBUG and so on but is not sanity-checked.

    Args:
        stream (object): must support write method
        level (str): informative severity level
        message (str): the message to be logged

    Returns:
        None
    """
    # format: ISO 8601
    ts = get_timestamp()
    fmt_msg = f"{ts} - LOG {level}\n{message.strip()}\n"
    stream.write(fmt_msg)
    return


DOCREC.add_function_doc(write_log_message)
