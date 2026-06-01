"""Module containing global variables
that expose fully resolved paths as
shorthand for the user. Using these
variables avoids common typo mistakes
such as switching from 'log/' to 'logs/'
somewhere in the workflow.
"""

_THIS_MODULE = ["commons", "30-settings", "20-environment", "05_paths.smk"]
_THIS_CONTEXT = DocContext.TEMPLATE

DOCREC.add_module_doc(_THIS_CONTEXT, _THIS_MODULE)

### === IMPORTANT === ###
### the following set of paths describe files
### and folders relative to the repository
### of the workflow, e.g., the location
### of the Snakefile itself. Except for the
### path to the conda environment files
### (variable DIR_ENVS), these variables
### are typically not needed to implement
### a new workflow (user-perspective).
###
### The paths to specify input/output files
### in a workflow are set in the second half
### of this file.

# start with all paths describing the repository
DIR_SNAKEFILE = pathlib.Path(workflow.basedir).resolve(strict=True)
assert DIR_SNAKEFILE.name == "workflow"  # by convention/best practices
PATH_SNAKEFILE = pathlib.Path(workflow.main_snakefile).resolve(strict=True)
NAME_SNAKEFILE = PATH_SNAKEFILE.stem
assert DIR_SNAKEFILE.samefile(PATH_SNAKEFILE.parent)
assert NAME_SNAKEFILE == "Snakefile"


DOCREC.add_member_doc(
    DocLevel.GLOBALVAR,
    "DIR_SNAKEFILE",
    DIR_SNAKEFILE,
    (
        "Fully resolved directory path in which the workflow's "
        "main snakefile resides. By convention, this path always "
        "ends with the last component `workflow/`."
    ),
)

DOCREC.add_member_doc(
    DocLevel.GLOBALVAR,
    "PATH_SNAKEFILE",
    PATH_SNAKEFILE,
    ("Fully resolved file path of the workflow's main snakefile."),
)

DOCREC.add_member_doc(
    DocLevel.GLOBALVAR,
    "NAME_SNAKEFILE",
    NAME_SNAKEFILE,
    (
        "Name of the workflow's main snakefile, which is always "
        "`Snakefile` by convention / best practices."
    ),
)


# If the name of the snakefile is not "Snakefile" and the
# developer has not set the devmode option, print a hint
# to help diagnose path resolution errors
if RUN_IN_TEST_MODE and not RUN_IN_DEV_MODE:
    hint_msg = (
        "\nDEV HINT:\n"
        "Looks like you are executing the builtin"
        " template testing module,"
        " but you did not set the config option:\n"
        " '--config devmode=True'\n"
        "This may lead to FileNotFoundErrors for the"
        " subfolders expected to exist"
        " (proc/, results/ and so on) in the working directory.\n"
        "This may of course be intended to actually test"
        " for passes/fails related to the assumed default"
        " directory structure.\nThat is, the code logic of"
        " the template will not interfere with the process,"
        " you have to know for yourself what you want to"
        " achieve here.\n\n"
    )
    sys.stderr.write(hint_msg)

DIR_REPOSITORY = DIR_SNAKEFILE.parent
DIR_REPO = DIR_REPOSITORY

DOCREC.add_member_doc(
    DocLevel.GLOBALVAR,
    "DIR_REPO",
    DIR_REPO,
    (
        "Recommended alias/shorthand for `DIR_REPOSITORY`, i.e. the fully "
        "resolved directory path to the workflow repository. By convention, "
        "this is always taken to be the parent of the `workflow/` directory. "
        "CAVEAT: typically, this path will correspond to the top-level folder "
        "of the repository ('the git root') but this is not checked."
    ),
)

# use of scripts is optional, but testing script is part
# of the template (= must resolve)
DIR_SCRIPTS = DIR_SNAKEFILE.joinpath(CONST_DIRS.scripts).resolve(strict=True)

DOCREC.add_member_doc(
    DocLevel.GLOBALVAR,
    "DIR_SCRIPTS",
    DIR_SCRIPTS,
    (
        "Fully resolved directory path to `[..]/workflow/scripts`. "
        "Any script used by the workflow can thus be addressed "
        "via `DIR_SCRIPTS.joinpath(...)`. "
        "See also the `get_script` function."
    ),
)

# must also exist because of the template's
# development and execution conda env/yaml
# files
DIR_ENVS = DIR_SNAKEFILE.joinpath(CONST_DIRS.envs).resolve(strict=True)

DOCREC.add_member_doc(
    DocLevel.GLOBALVAR,
    "DIR_ENVS",
    DIR_ENVS,
    (
        "Fully resolved directory path to `[..]/workflow/envs`. "
        "Any Conda environment yaml file used by the workflow "
        "can thus be addressed via `DIR_ENVS.joinpath(...)`."
    ),
)

### === IMPORTANT === ###
### the following set of paths describe files
### and folders relative to the specified
### Snakemake working directory, i.e.
### relative to 'snakemake -d <wd>'
### These variables are typically used
### to specify input/output paths in
### Snakemake rules.

# all paths describing the working directory
# plus default subfolders
DIR_WORKING = pathlib.Path(workflow.workdir_init).resolve(strict=True)
WORKDIR = DIR_WORKING

DOCREC.add_member_doc(
    DocLevel.GLOBALVAR,
    "DIR_WORKING",
    DIR_WORKING,
    (
        "Recommended global variable representing the fully resolved "
        "path to the Snakemake working directory, i.e. the content of "
        "the `--directory` / `-d` command line parameter. "
        "**CAUTION**: this parameter should only be used if absolutely "
        "necessary. All relevant directory paths should be addressed via "
        "the other global variables of this module."
    ),
)

DOCREC.add_member_doc(
    DocLevel.GLOBALVAR, "WORKDIR", WORKDIR, ("Alias/shorthand for `DIR_WORKING`.")
)

# if the workflow is executed in development mode,
# the default paths underneath the working directory
# may not exist and that is ok
WD_PATHS_MUST_RESOLVE = not RUN_IN_DEV_MODE

DOCREC.add_member_doc(
    DocLevel.DEVONLY,
    "WD_PATHS_MUST_RESOLVE",
    WD_PATHS_MUST_RESOLVE,
    (
        "If the workflow is executed with `--config devmode=True`, "
        "non-existing default paths are ignored and do not raise an error."
    ),
)

WD_ABSPATH_PROCESSING = CONST_DIRS.proc.resolve(strict=WD_PATHS_MUST_RESOLVE)
WD_RELPATH_PROCESSING = WD_ABSPATH_PROCESSING.relative_to(DIR_WORKING)
# recommended shorthand for 'processing' folder:
DIR_PROC = WD_RELPATH_PROCESSING

DOCREC.add_member_doc(
    DocLevel.GLOBALVAR,
    "DIR_PROC",
    DIR_PROC,
    (
        f"Relative path pointing to `{CONST_DIRS.proc}` "
        "in the `WORKDIR`. All non-result files of the "
        "workflow can be addressed via `DIR_PROC.joinpath(...)` "
        "in Snakemake rules."
    ),
)

WD_ABSPATH_RESULTS = CONST_DIRS.results.resolve(strict=WD_PATHS_MUST_RESOLVE)
WD_RELPATH_RESULTS = WD_ABSPATH_RESULTS.relative_to(DIR_WORKING)
# recommended shorthand for 'results' folder:
DIR_RES = WD_RELPATH_RESULTS

DOCREC.add_member_doc(
    DocLevel.GLOBALVAR,
    "DIR_RES",
    DIR_RES,
    (
        f"Relative path pointing to `{CONST_DIRS.results}` "
        "in the `WORKDIR`. All result files of the "
        "workflow can be addressed via `DIR_RES.joinpath(...)` "
        "in Snakemake rules."
    ),
)

WD_ABSPATH_LOG = CONST_DIRS.log.resolve(strict=WD_PATHS_MUST_RESOLVE)
WD_RELPATH_LOG = WD_ABSPATH_LOG.relative_to(DIR_WORKING)
# recommended shorthand for 'log' folder:
DIR_LOG = WD_RELPATH_LOG

DOCREC.add_member_doc(
    DocLevel.GLOBALVAR,
    "DIR_LOG",
    DIR_LOG,
    (
        f"Relative path pointing to `{CONST_DIRS.log}` "
        "in the `WORKDIR`. All log files of the "
        "workflow can be addressed via `DIR_LOG.joinpath(...)` "
        "in Snakemake rules."
    ),
)

WD_ABSPATH_RSRC = CONST_DIRS.rsrc.resolve(strict=WD_PATHS_MUST_RESOLVE)
WD_RELPATH_RSRC = WD_ABSPATH_RSRC.relative_to(DIR_WORKING)
# recommended shorthand for 'rsrc' [benchmark] folder:
DIR_RSRC = WD_RELPATH_RSRC
DIR_BENCHMARK = DIR_RSRC

DOCREC.add_member_doc(
    DocLevel.GLOBALVAR,
    "DIR_RSRC",
    DIR_RSRC,
    (
        f"Relative path pointing to `{CONST_DIRS.rsrc}` "
        "in the `WORKDIR`. All resource ('benchmark') "
        "files of the workflow can be addressed via "
        "`DIR_LOG.joinpath(...)` in Snakemake rules."
    ),
)

DOCREC.add_member_doc(
    DocLevel.GLOBALVAR,
    "DIR_BENCHMARK",
    DIR_BENCHMARK,
    (
        f"Relative path pointing to `{CONST_DIRS.rsrc}` "
        "in the `WORKDIR`. Alias for DIR_RSRC."
    ),
)

WD_ABSPATH_CLUSTERLOG_OUT = CONST_DIRS.cluster_log_out.resolve(
    strict=WD_PATHS_MUST_RESOLVE
)
WD_RELPATH_CLUSTERLOG_OUT = WD_ABSPATH_CLUSTERLOG_OUT.relative_to(DIR_WORKING)
DIR_CLUSTERLOG_OUT = WD_RELPATH_CLUSTERLOG_OUT

DOCREC.add_member_doc(
    DocLevel.GLOBALVAR,
    "DIR_CLUSTERLOG_OUT",
    DIR_CLUSTERLOG_OUT,
    (
        f"Relative path pointing to `{CONST_DIRS.cluster_log_out}` "
        "in the `WORKDIR`. Only relevant in HPC environments. "
        "Intended to capture all stdout streams of executed rules/jobs "
        "(if applicable)."
    ),
)

WD_ABSPATH_CLUSTERLOG_ERR = CONST_DIRS.cluster_log_err.resolve(
    strict=WD_PATHS_MUST_RESOLVE
)
WD_RELPATH_CLUSTERLOG_ERR = WD_ABSPATH_CLUSTERLOG_ERR.relative_to(DIR_WORKING)
DIR_CLUSTERLOG_ERR = WD_RELPATH_CLUSTERLOG_ERR

DOCREC.add_member_doc(
    DocLevel.GLOBALVAR,
    "DIR_CLUSTERLOG_ERR",
    DIR_CLUSTERLOG_ERR,
    (
        f"Relative path pointing to `{CONST_DIRS.cluster_log_err}` "
        "in the `WORKDIR`. Only relevant in HPC environments. "
        "Intended to capture all stderr streams of executed rules/jobs "
        "(if applicable)."
    ),
)

WD_ABSPATH_GLOBAL_REF = CONST_DIRS.global_ref.resolve(strict=WD_PATHS_MUST_RESOLVE)
WD_RELPATH_GLOBAL_REF = WD_ABSPATH_GLOBAL_REF.relative_to(DIR_WORKING)
# recommended shorthand for 'global_ref' [external/global references] folder:
DIR_GLOBAL_REF = WD_RELPATH_GLOBAL_REF

DOCREC.add_member_doc(
    DocLevel.GLOBALVAR,
    "DIR_GLOBAL_REF",
    DIR_GLOBAL_REF,
    (
        f"Relative path pointing to `{CONST_DIRS.global_ref}` "
        "in the `WORKDIR`. This default directory is the source "
        "location for all reference data files that are *not* "
        "being produced by the workflow itself."
    ),
)

WD_ABSPATH_LOCAL_REF = CONST_DIRS.local_ref.resolve(strict=WD_PATHS_MUST_RESOLVE)
WD_RELPATH_LOCAL_REF = WD_ABSPATH_LOCAL_REF.relative_to(DIR_WORKING)
# recommended shorthand for 'local_ref' [internal references] folder:
DIR_LOCAL_REF = WD_RELPATH_LOCAL_REF

DOCREC.add_member_doc(
    DocLevel.GLOBALVAR,
    "DIR_LOCAL_REF",
    DIR_LOCAL_REF,
    (
        f"Relative path pointing to `{CONST_DIRS.local_ref}` "
        "in the `WORKDIR`. This default directory is the target "
        "and source location for all reference data files that "
        "are produced programmatically by the workflow itself. "
        f"In other words, for each file in `{CONST_DIRS.local_ref}`, "
        "there must be a rule in the workflow that produces that file."
    ),
)
