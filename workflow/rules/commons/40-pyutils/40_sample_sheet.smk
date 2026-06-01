import io
import pandas

_THIS_MODULE = ["commons", "40-pyutils", "40_sample_sheet.smk"]
_THIS_CONTEXT = DocContext.TEMPLATE

DOCREC.add_module_doc(_THIS_CONTEXT, _THIS_MODULE)


def _buffer_sample_sheet(file_path):
    """"""
    buffer = io.StringIO()
    with open(file_path, "r") as table:
        for line in table:
            if not line.strip() or line.startswith("#"):
                continue
            clean_columns = [entry.strip() for entry in line.strip().split("\t")]
            buffer.write("\t".join(clean_columns) + "\n")
    buffer.seek(0)
    return buffer


def read_sample_sheet(file_path, column_def):
    """This function reads a TSV text file that is assumed
    to represent a valid sample sheet for the workflow.
    The reading process ignores empty and '#'-prefixed lines
    (typically, in-line comments) and, via the 'column_def'
    parameter, performs basic standardization of the sample sheet
    header such that the resulting dataframe has only well-behaved
    column names.

    Args:
        file_path (str | pathlib.Path): the TSV file path,
            should be passed via the SAMPLE_SHEET_PATH global variable
        column_def (MandatorySampleSheetColumns): object defining the
            mandatory columns for the sample sheet

    Returns:
        sample_sheet (pandas.DataFrame): the sample sheet,
            assigned to the global variable SAMPLE_SHEET

    Raises:
        ValueError: indirect via column_def.norm_column_name()
        RuntimeError: not all mandatory columns present in input sample sheet
    """
    buffered_sheet = _buffer_sample_sheet(file_path)

    sample_sheet = pandas.read_csv(buffered_sheet, sep="\t")

    old_names = sample_sheet.columns
    new_names = [column_def.norm_column_name(col) for col in old_names]
    if VERBOSE:
        logerr(f"Normalizing sample sheet header from {old_names} --- to {new_names}")
    sample_sheet.columns = new_names

    missing = []
    for col in column_def.get_mandatory_column_names():
        if col not in new_names:
            missing.append(col)

    if missing:
        err_msg = (
            "The following mandatory column names are missing from the "
            f"sample sheet header - please fix your sample sheet: {missing}"
        )
        logerr(err_msg)
        raise RuntimeError(err_msg)

    return sample_sheet


DOCREC.add_function_doc(read_sample_sheet)
