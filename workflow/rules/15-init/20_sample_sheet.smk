
import pathlib


# This workflow must be executed with a sample sheet, i.e.
# snakemake [...] --config samples=path/to/sample/sheet/table.tsv
# is the expected command line call for start the workflow.

# default sample sheet reading operation in rules::10_sample_sheet.smk
assert SAMPLE_SHEET is not None


def parse_fofn_file(fofn_file):
    """Read a file listing file paths and return sorted list.
    """

    file_paths = []
    error_paths = []
    with open(fofn_file, "r") as listing:
        for line in listing:
            path = pathlib.Path(line.strip())
            if not path.is_file():
                error_paths.append(path)
            else:
                file_paths.append(path)

    if error_paths:
        err_msg = (
            f"Error: the following sample input files read from {fofn_file} "
            f"are not accessible: {sorted(error_paths)}"
        )
        logerr(err_msg)
        raise ValueError(err_msg)

    if not file_paths:
        err_msg = f"Error: no files loaded from fofn input: {fofn_file}"
        logerr(err_msg)
        raise ValueError(err_msg)

    return sorted(file_paths)


def collect_input_files_per_sample(sample, sample_input_files):
    """
    """
    specified_paths = [
        path.strip() for path in sample_input_files.split(",")
    ]

    if not specified_paths:
        err_msg = (
            f"Error: no input data (read files) in sample sheet for sample: {sample}"
        )
        logerr(err_msg)
        raise ValueError(err_msg)

    file_paths = []
    error_paths = []
    for file_path in specified_paths:
        # option 1: it's a file listing / file of file names
        path = pathlib.Path(file_path)
        if path.is_file() and path.suffix in [".fof", ".fofn", ".fofp", ".flst", ".lst"]:
            parsed_files = parse_fofn_file(path)
            file_paths.extend(parsed_files)
            continue
        # option 2: it's simply a valid file path, either absolute somewhere
        # on the file system or underneath the Snakemake working dir
        if path.is_file():
            file_paths.append(path)
            continue
        # option 3: it's not accessible
        error_paths.append(file_path)
        continue

    if error_paths:
        err_msg = (
            "Error: the following sample input files are not accessible: "
            f"{sorted(error_paths)}"
        )
        logerr(err_msg)
        raise ValueError(err_msg)

    num_gzipped_input = sum(1 if path.suffix == ".gz" else 0 for path in file_paths)
    num_plain_input = sum(0 if path.suffix == ".gz" else 1 for path in file_paths)
    assert num_gzipped_input + num_plain_input == len(file_paths)

    if num_gzipped_input > 0 and num_plain_input > 0:
        err_msg = (
            f"Error: mixed input (gzipped and plain) for sample {sample } is not supported. "
            "Either all or none of the input files per sample must be gzipped."
        )
        raise ValueError(err_msg)

    all_gzipped = num_gzipped_input > 0

    return all_gzipped, file_paths


_PREP_SAMPLE_INPUT = [
    (row.sample, collect_input_files_per_sample(row.sample, row.input_path))
    for row in SAMPLE_SHEET.itertuples()
]

SAMPLE_INPUT_FILES = dict(
    (sample, sample_files) for (sample, (_, sample_files)) in _PREP_SAMPLE_INPUT
)

SAMPLE_COMPRESSED_INPUT = dict(
    (sample, all_gzipped) for (sample, (all_gzipped, _)) in _PREP_SAMPLE_INPUT
)

VALID_SEQUENCING_TECH = {"sr", "hifi", "ont"}


def validate_sample_tech(sample, tech):
    tech = str(tech).strip().lower()
    if tech not in VALID_SEQUENCING_TECH:
        err_msg = (
            f"Error: sample '{sample}' has invalid 'tech' value '{tech}' in "
            f"the sample sheet - must be one of {sorted(VALID_SEQUENCING_TECH)}."
        )
        logerr(err_msg)
        raise ValueError(err_msg)
    return tech


if RUN_LOCITYPER:
    if "tech" not in SAMPLE_SHEET.columns:
        err_msg = (
            "Error: locityper was selected (tools=...) but the sample sheet "
            "does not contain a 'tech' column. Please add a 'tech' column "
            f"with one of {sorted(VALID_SEQUENCING_TECH)} per sample."
        )
        logerr(err_msg)
        raise ValueError(err_msg)

    SAMPLE_TECH = dict(
        (row.sample, validate_sample_tech(row.sample, row.tech))
        for row in SAMPLE_SHEET.itertuples()
    )
else:
    SAMPLE_TECH = {}