"""This module implements the functions to
create the workflow manifest aka provides the
necessary utilities to perform the file accounting.
To non-template (workflow) developers, the
register_* functions are the only relevant ones
that must be used as parameters in the Snakemake
rules where input, output or reference files
shall be recorded (be part of the manifest).
"""

import hashlib
import pathlib
import pickle

# locking capability potentially
# needed for file accounting;
# in the current implementation
# (only update during dry run)
# probably not needed
import portalocker


_THIS_MODULE = ["commons", "40-pyutils", "85_template_accounting.smk"]
_THIS_CONTEXT = DocContext.TEMPLATE

DOCREC.add_module_doc(_THIS_CONTEXT, _THIS_MODULE)


def _add_file_to_account(accounting_file, fmt_records):
    """
    Add registered files to the respective accounting file;
    do not duplicate records by caching the set of known path
    ids in a separate (pickle dump) file.
    """
    lockfile = pathlib.Path(accounting_file).with_suffix(".lock")
    path_id_file = pathlib.Path(accounting_file).with_suffix(".paths.pck")
    with portalocker.Lock(lockfile, "a", timeout=WAIT_ACC_LOCK_SECS) as lock:
        try:
            with open(path_id_file, "rb") as path_id_dump:
                known_path_ids = pickle.load(path_id_dump)
        except (FileNotFoundError, EOFError):
            known_path_ids = set()

        with open(accounting_file, "a") as account:
            for path_id, path_records in fmt_records:
                if path_id in known_path_ids:
                    continue
                _ = account.write(path_records)
                known_path_ids.add(path_id)

        with open(path_id_file, "wb") as path_id_dump:
            _ = pickle.dump(known_path_ids, path_id_dump)
    return


def _add_checksum_files(add_files, subfolder):
    """
    Augment each file registered for manifest inclusion
    with three additional files recording md5 and sha256
    checksums and the file size in bytes.
    """
    formatted_records = []
    for add_file in add_files:
        file_name = add_file.name
        abspath = str(add_file.resolve(strict=False))
        path_id = hashlib.md5(abspath.encode("utf-8")).hexdigest()
        md5_checksum = DIR_PROC.joinpath(
            ".accounting", "checksums", f"{subfolder}", f"{file_name}.{path_id}.md5"
        )
        sha256_checksum = DIR_PROC.joinpath(
            ".accounting", "checksums", f"{subfolder}", f"{file_name}.{path_id}.sha256"
        )
        size_file = DIR_PROC.joinpath(
            ".accounting", "file_sizes", f"{subfolder}", f"{file_name}.{path_id}.bytes"
        )
        formatted_records.append(
            (
                path_id,
                f"{add_file}\t{path_id}\t{subfolder}\tdata\n"
                + f"{md5_checksum}\t{path_id}\t{subfolder}\tchecksum\n"
                + f"{sha256_checksum}\t{path_id}\t{subfolder}\tchecksum\n"
                + f"{size_file}\t{path_id}\t{subfolder}\tsize\n",
            )
        )

    return formatted_records


def register_input(*args, allow_non_existing=False):
    """
    TODO: potential breaking change - ?
    Fix English for keyword argument: 'allow_non_existent'

    The 'register_input(...)' function must be used
    to register all files in the file accounting process
    that should appear as workflow input files in the
    final (file) manifest. Its use should have the following
    form:

    rule some_rule_name:
        input:
            ...
        params:
            acc_in=lambda wildcards, input: register_input(input)

    The above would register all files of the 'input' object
    as workflow input files and compute checksums and file sizes
    for all of them to be included in the workflow file manifest.

    Notably, this function assumes that all files exist when the
    workflow starts / the function is called, which is a logical
    necessity. There are edge cases such as the run config dump
    file, which is created as part of the workflow run and yet
    considered an input file (= no workflow run w/o config file).

    This register function has slightly
    different semantics because input files
    should always exist when the workflow starts.
    For special cases, a keyword-only argument can
    be set to accept non-existent files when the
    pipeline run starts and yet the files should
    be counted as input files. One of those
    special cases is the config dump, which is
    counted as part of the input (cannot run
    the workflow w/o config), but the dump
    is only created after execution.

    Args:
        args (any): a file path or a potentially nested object
            containing many file paths to be registered as
            workflow input files.
        allow_non_existing (bool): do not raise for non-existent files

    Returns:
        None: must be constant to avoid rerun triggers
            because of changing rule parameters.
    """
    if DRYRUN:
        accounting_file = ACCOUNTING_FILES["inputs"]
        input_files = flatten_nested_paths(args)
        if not allow_non_existing:
            err_msg = ""
            for file_path in input_files:
                if not file_path.exists():
                    err_msg += (
                        f"register_input() -> input file does not exist: {file_path}\n"
                    )
                elif file_path.is_dir():
                    err_msg += f"Specified input is not a regular file: {file_path}\n"
                else:
                    pass
            if err_msg:
                err_msg = f"\nINPUT ERROR:\n{err_msg}"
                logerr(err_msg)
                raise RuntimeError("Bad input files detected (see above)")
        fmt_records = _add_checksum_files(input_files, "inputs")
        _add_file_to_account(accounting_file, fmt_records)
    return None


DOCREC.add_function_doc(register_input)


def register_reference(*args):
    """
    Register reference file(s) for the workflow manifest.
    The difference between 'input' and 'reference' is mostly
    semantics, i.e., scientists typically distinguish between
    these two categories and so do we.

    Args:
        args (any): a file path or a potentially nested object
            containing many file paths to be registered as
            workflow input files.
    Returns:
        None: must be constant to avoid rerun triggers
            because of changing rule parameters.

    """
    if DRYRUN:
        accounting_file = ACCOUNTING_FILES["references"]
        reference_files = flatten_nested_paths(args)
        fmt_records = _add_checksum_files(reference_files, "references")
        _add_file_to_account(accounting_file, fmt_records)
    return None


DOCREC.add_function_doc(register_reference)


def register_result(*args):
    """
    Register reference file(s) for the workflow manifest.
    The difference between 'input' and 'reference' is mostly
    semantics, i.e., scientists typically distinguish between
    these two categories and so do we.

    Args:
        args (any): a file path or a potentially nested object
            containing many file paths to be registered as
            workflow input files.
    Returns:
        None: must be constant to avoid rerun triggers
            because of changing rule parameters.

    """
    if DRYRUN:
        accounting_file = ACCOUNTING_FILES["results"]
        result_files = flatten_nested_paths(args)
        fmt_records = _add_checksum_files(result_files, "results")
        _add_file_to_account(accounting_file, fmt_records)
    return None


DOCREC.add_function_doc(register_result)


def load_accounting_information(wildcards):
    """
    This function loads the file paths from all
    three accounting files to force creation
    (relevant for checksum and size files).

    Args:
        wildcards: required argument because the function
        is called as an input function of a Snakemake rule;
        wildcards are not processed in this function
        (constant output)
    Returns:
        List[str] : the file paths of the three
        accounting files (input, reference and results)

    """
    created_files = []
    for account_name, account_file in ACCOUNTING_FILES.items():
        if VERBOSE:
            logerr(f"Loading file account {account_name}")
        try:
            with open(account_file, "r") as account:
                created_files.extend(
                    [l.split()[0] for l in account.readlines() if l.strip()]
                )
            if VERBOSE:
                logerr(f"Size of accounting file list: {len(created_files)}")
        except FileNotFoundError:
            if VERBOSE:
                warn_msg = f"Accounting file does not exist (yet): {account_file}\n"
                warn_msg += "Please RERUN the workflow in DRY RUN MODE to create the file accounts!"
                logerr(warn_msg)
    return sorted(created_files)


DOCREC.add_function_doc(load_accounting_information)


def load_file_by_path_id(wildcards):
    """
    Simple utility function that extracts
    the source file path from the accounting
    files.

    Args:
        wildcards: contains the wildcards to select
            the correct account type (input, reference, result)
            and the path ID that uniquely identifies
            the file.
    Returns:
        str: source file path
    """
    account_type = wildcards.file_type
    assert account_type in ACCOUNTING_FILES
    account_file = ACCOUNTING_FILES[account_type]

    req_path_id = wildcards.path_id
    req_file = None
    with open(account_file, "r") as account:
        for line in account:
            # note here: the data file is always
            # first in the list of four entries
            file_path, file_path_id = line.split()[:2]
            if file_path_id != req_path_id:
                continue
            req_file = file_path
            break
    if req_file is None:
        logerr(
            f"Failed loading file with path ID {req_path_id} from accounting file {account_file}"
        )
        raise FileNotFoundError(
            f"Missing file: {wildcards.file_type} / {wildcards.file_name}"
        )

    return req_file


DOCREC.add_function_doc(load_file_by_path_id)


def _load_data_line(file_path):
    """
    Simple utility function that reads the file metadata
    (= file size or checksums) from the respective files
    on disk.

    Args:
        file_path: path to metadata file, i.e. *.md5 / *.bytes / *.sha256
    Returns:
        str: the respective metadata value, i.e. a checksum or file size
    """
    with open(file_path, "r") as dump:
        content = dump.readline().strip().split()[0]
    return content


DOCREC.add_function_doc(_load_data_line)


def process_accounting_record(line):
    """
    This function is called for each entry in the accounting
    files (= one input, reference or result file) and then
    determines what information has to be gathered:
    checksum / size / file metadata such as name.

    Args:
        line: a string line from an accounting file
    Returns:
        str, dict: the path ID (= unique file key) and
            the collected metadata such as the file
            checksum or size
    """
    path, path_id, file_category, record_type = line.strip().split()
    if record_type == "data":
        record = {
            "file_path": path,
            "file_name": pathlib.Path(path).name,
            "file_category": file_category,
            "path_id": path_id,
        }
    elif record_type == "checksum":
        checksum_type = path.rsplit(".", 1)[-1]
        record = {
            f"file_checksum_{checksum_type}": _load_data_line(path),
            "path_id": path_id,
        }
    elif record_type == "size":
        size_unit = path.rsplit(".", 1)[-1]
        record = {
            f"file_size_{size_unit}": int(_load_data_line(path)),
            "path_id": path_id,
        }
    return path_id, record


DOCREC.add_function_doc(process_accounting_record)
