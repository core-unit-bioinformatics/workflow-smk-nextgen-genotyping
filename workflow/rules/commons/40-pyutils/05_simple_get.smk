"""This module implements simple
'getter' type of functions to obtain
some small piece of information.
As a rule of thumb for developers,
functions in this module should require
only minimal input (parameters), provide
a well-defined (simple) output
--- preferably as a primitive datatype ---
and should not call other custom functions in
their body.
"""

import datetime
import getpass
import pathlib
import socket


_THIS_MODULE = ["commons", "40-pyutils", "05_simple_get.smk"]
_THIS_CONTEXT = DocContext.TEMPLATE

DOCREC.add_module_doc(_THIS_CONTEXT, _THIS_MODULE)


def get_username():
    """
    Returns:
        user (str): login name of current user
    """
    user = getpass.getuser()
    return user


DOCREC.add_function_doc(get_username)


def get_hostname():
    """
    Returns:
        host (str): name of host machine
    """
    host = socket.gethostname()
    return host


DOCREC.add_function_doc(get_hostname)


def get_timestamp():
    """
    Get naive (not timezone-aware)
    timestamp representing 'now'.
    The formatting is following
    ISO 8601 w/o timezone offset, i.e.
    YYYY-MM-DDThh-mm-ss
    (24-hour format for time)

    Returns:
        ts (str): timestamp of 'now' w/o tz
    """
    # format: ISO 8601
    ts = datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    return ts


DOCREC.add_function_doc(get_timestamp)


def get_script(script_name, extension="py"):
    """
    Utility function to locate script files underneath
    DIR_SCRIPTS. The intended usage context is inside
    a 'params' block, i.e.:

    rule rule_with_script:
            [...]
        params:
            script = get_script("script_name")
        shell:
            '{params.script} [...do scripted task...]'

    Args:
        script_name (str): file name of the script to be located
        extension (str): file extension of the script to be locate; default 'py'

    Returns:
        selected_script (str): full path to script file

    Raises:
        ValueError: no script or more than one match found

    """
    predicate = lambda s: script_name == s.stem or script_name == s.name

    # DIR_SCRIPTS is set in common/constants
    all_scripts = DIR_SCRIPTS.glob(f"**/*.{extension.strip('.')}")
    retained_scripts = list(map(str, filter(predicate, all_scripts)))
    if len(retained_scripts) != 1:
        if len(retained_scripts) == 0:
            err_msg = (
                f"No scripts found or retained starting at '{DIR_SCRIPTS}' "
                f" and looking for '{script_name}' [+ .{extension}]"
            )
        else:
            ambig_scripts = "\n".join(retained_scripts)
            err_msg = f"Ambiguous script name '{script_name}':\n{ambig_scripts}\n"
        raise ValueError(err_msg)
    selected_script = retained_scripts[0]

    return selected_script


DOCREC.add_function_doc(get_script)


def find_script(script_name, extension="py"):
    """
    Original version of 'get_script'.

    DEPRECATED FUNCTION --- see 'get_script'
    """
    warn_msg = (
        "commons::40-pyutils::00_simple_get.smk\n"
        "=== Deprecation warning ===\n"
        "The function 'find_script' is deprecated "
        "and will be removed in a future update.\n"
        "Call 'get_script(script_name, extension)' instead.\n"
        "===========================\n"
    )
    logerr(warn_msg)
    return get_script(script_name, extension)


DOCREC.add_function_doc(find_script)
