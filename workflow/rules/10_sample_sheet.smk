"""
This module is part of the workflow template but will
only be created if it does not exist - it must never be
updated (= overwritten) because it is supposed to be
extended by the workflow developer as needed.

The MandatorySampleSheetColumns dataclass must be extended
with additional columns when needed in the respective workflow.

=== Concrete example

By default, a valid sample sheet must contain the two columns
'sample' and 'input_path'.
See the template commons module
> rules::commons::10-constants::40_sheet_columns.smk
for the respective code, which also illustrates how to extend
the class below.

Extending the code by requiring, e.g., a 'karyotype' column to be
present in the sample sheet works as follows:

(1) Add a 'KaryotypeColumn' enum type to this module; the primary
name/alias for this column has to be manually set to the number 0.
All secondary aliases must be set to 'enum.auto()', which continues
enumeration at 1.


class KaryotypeColumn(enum.Enum):
    karyotype = 0
    sex = enum.auto()
    gender = enum.auto()


(2) Extend the 'MandatorySampleSheetColumns' class below by adding
the karyotype column:


@dataclasses.dataclass(frozen=True)
class MandatorySampleSheetColumns(MinimalSampleSheetColumns):

    # this adds the attribute 'karyotype' to the class
    karyotype: str = KaryotypeColumn(0).name

    def __post_init__(self):
        super().__post_init__()

        # this adds all aliases of 'karyotype' to the class
        self._update_alias_names(KaryotypeColumn)
        return


(3) Repeat this for all *mandatory* columns

(4) In the rest of the workflow, access the columns in the
sample sheet (= pandas.DataFrame) as follows:

SAMPLE_SHEET[MSSC.karyotype]  # returns the respective pandas.Series
# the MSSC global variable is a shorthand (see actual code below)

"""

import dataclasses
import enum

_THIS_MODULE = ["10_sample_sheet.smk"]
_THIS_CONTEXT = DocContext.TEMPLATE

DOCREC.add_module_doc(_THIS_CONTEXT, _THIS_MODULE)


@dataclasses.dataclass(frozen=True)
class MandatorySampleSheetColumns(MinimalSampleSheetColumns):

    def __post_init__(self):
        super().__post_init__()
        return


MANDATORY_SAMPLE_SHEET_COLUMNS = MandatorySampleSheetColumns()
MSSC = MANDATORY_SAMPLE_SHEET_COLUMNS

# note to devs:
# SAMPLE_SHEET_PATH is defined in
# commons::30-settings::20-environment::10_file_constants.smk
if SAMPLE_SHEET_PATH:
    SAMPLE_SHEET = read_sample_sheet(SAMPLE_SHEET_PATH, MSSC)
    SAMPLES = sorted(set(SAMPLE_SHEET[MSSC.sample].values))
else:
    SAMPLE_SHEET = None
    SAMPLES = []


DOCREC.add_member_doc(
    DocLevel.GLOBALOBJ,
    "MANDATORY_SAMPLE_SHEET_COLUMNS",
    MANDATORY_SAMPLE_SHEET_COLUMNS,
    (
        "Global object that holds the names of all columns "
        "that are *mandatory* in a sample sheet of the workflow "
        "to be valid. The documentation context of this object is "
        "TEMPLATE because in its minimal form, this object just "
        "represents the two columns 'sample' and 'input_path', which "
        "are always required. The object will typically be adapted in "
        "a workflow-specific way (find a detailed how-to in the module "
        "doc string). End users must find the information about mandatory "
        "columns in a valid sample sheet in the main readme of the workflow "
        "repository and, potentially, a more detailed description in the "
        "`docs/` subfolder of the repository; in other words, this help is "
        "targeting workflow developers."
    ),
)

DOCREC.add_member_doc(
    DocLevel.GLOBALOBJ,
    "MSSC",
    MSSC,
    ("Alias/shorthand for MANDATORY_SAMPLE_SHEET_COLUMNS"),
)


DOCREC.add_member_doc(
    DocLevel.GLOBALOBJ,
    "SAMPLE_SHEET",
    SAMPLE_SHEET,
    (
        "Global object representing the complete sample sheet if specified. "
        "This object is either None or a pandas.DataFrame. For example, if the "
        "workflow template tests are executed, no sample sheet is specified at "
        "the invocation command line (`snakemake [...] run_tests`) and SAMPLE_SHEET "
        "is consequently set to None. "
        "The sample sheet (dataframe) can contain an arbitrary number of rows and "
        "columns, and, by construction, it is only guaranteed that the mandatory "
        "sample sheet columns are present. However, no value sanity checking or "
        "the like is performed at runtime"
    ),
)
