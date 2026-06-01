"""The staging module is the place to put
functions that should only be executed when
Snakemake is ready to run, i.e., all variables
have been initialized, all dry run data have
been collected and so on.

Additions to this module are only allowed
under the "if absolutely necessary" rule
and should not require any further interaction.

Remember to call all functions from this
module in commons::90_staging.smk
"""

_THIS_MODULE = ["commons", "40-pyutils", "90_template_staging.smk"]
_THIS_CONTEXT = DocContext.TEMPLATE

DOCREC.add_module_doc(_THIS_CONTEXT, _THIS_MODULE)


def _reset_file_accounts():
    """
    Why is this function needed?
    - The way the file accounting currently caches
    the entries about file metadata to produce (checksums
    and file size) can lead to errors during development
    of a workflow when fileA is replaced by fileB, but
    the accounting cache still contains fileA.md5,
    fileA.sha256 and fileA.size, which can no longer
    be generated because fileA is no longer produced
    by the workflow.

    In this case, the user needs to manually reset the
    file accounting cache via

    snakemake [...] --config resetacc=True [...]

    Notably, this only resets the cache, it does not
    delete already computed metadata files. After that,
    the user can simply update the cache as usual by
    running the workflow in dry run mode twice.

    TODO:
    - implement a clean up step that deletes metadata files
    that are no longer needed (little volume, but can be many
    files)
    - make caching dynamic to allow auto-delete of metadata
    entries that refer to non-existent files (dangerous because
    it may obscrue errors).

    Args:
        <none>
    Returns:
        <none>

    """
    if RESET_ACCOUNTING:
        for acc_name, acc_path in ACCOUNTING_FILES.items():
            if VERBOSE:
                logerr(f"Resetting accounting file {acc_name}")
            try:
                with open(acc_path, "w"):
                    pass
            except FileNotFoundError:
                pass
            # important: reset cached path IDs
            path_id_cache = pathlib.Path(acc_path).with_suffix(".paths.pck")
            try:
                with open(path_id_cache, "w"):
                    pass
            except FileNotFoundError:
                pass

    for acc_file_path in ACCOUNTING_FILES.values():
        acc_path = pathlib.Path(acc_file_path).parent
        acc_path.mkdir(exist_ok=True, parents=True)

    return


DOCREC.add_function_doc(_reset_file_accounts)
