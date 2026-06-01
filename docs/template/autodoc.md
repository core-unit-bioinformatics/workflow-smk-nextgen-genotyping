# Parameter and function docs for context: TEMPLATE

## Module: 10_sample_sheet.smk

**Module file**: `workflow/rules/10_sample_sheet.smk`

### Documentation level: GLOBALOBJ

1. MANDATORY_SAMPLE_SHEET_COLUMNS
    - datatype: <class 'MandatorySampleSheetColumns'>
    - documentation: Global object that holds the names of all columns that are *mandatory* in a sample sheet of the workflow to be valid. The documentation context of this object is TEMPLATE because in its minimal form, this object just represents the two columns 'sample' and 'input_path', which are always required. The object will typically be adapted in a workflow-specific way (find a detailed how-to in the module doc string). End users must find the information about mandatory columns in a valid sample sheet in the main readme of the workflow repository and, potentially, a more detailed description in the `docs/` subfolder of the repository; in other words, this help is targeting workflow developers.
2. MSSC
    - datatype: <class 'MandatorySampleSheetColumns'>
    - documentation: Alias/shorthand for MANDATORY_SAMPLE_SHEET_COLUMNS
3. SAMPLE_SHEET
    - datatype: <class 'NoneType'>
    - documentation: Global object representing the complete sample sheet if specified. This object is either None or a pandas.DataFrame. For example, if the workflow template tests are executed, no sample sheet is specified at the invocation command line (`snakemake [...] run_tests`) and SAMPLE_SHEET is consequently set to None. The sample sheet (dataframe) can contain an arbitrary number of rows and columns, and, by construction, it is only guaranteed that the mandatory sample sheet columns are present. However, no value sanity checking or the like is performed at runtime

## Module: Snakefile

**Module file**: `workflow/Snakefile`

### Documentation level: TARGETRULE

1. run_all
    - datatype: <class 'snakemake.rules.Rule'>
    - documentation: 
```
    This is the default target rule to trigger
    the execution of all rules in the workflow.
    The 'run_all' rule includes the following three
    templated workflow tasks:
    1. dump the workflow config object into the results/ folder
    2. copy the sample sheet into the results/ folder (if applicable)
    3. create the workflow manifest file in the results/ folder (if applicable)

    The object 'WORKFLOW_OUTPUT' is a simple list containing all
    workflow outputs (files). This list is created in the module
    rules::commons::99_aggregate.smk
```
2. run_all_no_manifest
    - datatype: <class 'snakemake.rules.Rule'>
    - documentation: 
```
    This rule is an alternative target to the
    'run_all' rule that triggers the same series
    of rule executions except for NOT creating
    the workflow manifest file. Use this rule
    as target in case of problems with creating
    the workflow manifest file.
    For more details, see the documentation
    of the rule 'run_all'.
```
3. run_build_docs
    - datatype: <class 'snakemake.rules.Rule'>
    - documentation: 
```
    Target this rule to update the auto-generated
    documentation. This only updates the files:
    docs/template/autodoc.md - template dev only
    docs/workflow/autodoc.md - workflow dev only
    This rule has no file input dependencies and
    can always be executed.
```
4. run_tests
    - datatype: <class 'snakemake.rules.Rule'>
    - documentation: 
```
    This rule triggers executing the testing
    module of the workflow template located in
    rules::commons::99-testing::*
    The tests must succeed in all environments
    (e.g., local/laptop or managed/HPC cluster)
    unless explicitly designed for failure. Note
    that running the tests only checks for a working
    Snakemake setup and complete template because
    the 'include' of any workflow-specific
    (= non-template) modules is skipped.
    The other targets of this rule are identical
    to the 'run_all' rule; see that documentation
    for details.
```
5. run_tests_no_manifest
    - datatype: <class 'snakemake.rules.Rule'>
    - documentation: 
```
    The analogous rule to 'run_all_no_manifest'
    for running the tests w/o creating a file
    manifest. See the documentation of
    'run_all_no_manifest' for details.
```

## Module: commons::05_docgen.smk

**Module file**: `workflow/rules/commons/05_docgen.smk`

### Documentation level: GLOBALOBJ

1. DOCREC
    - datatype: <class 'DocRecorder'>
    - documentation: Alias/short hand for DOC_RECORDER.
2. DOC_RECORDER
    - datatype: <class 'DocRecorder'>
    - documentation: Instance of the `DocRecorder` class that is globally available to record documentation *in place*. The DocRecorder class has *four* member functions to record documentation about 'objects' (in the Python sense) in module contexts. At the beginning of each module, call the function **(1)** `DOC_RECORDER.add_module_doc(...)` to start a new module context. After that, call the function **(2)** `DOC_RECORDER.add_member_doc(...)` for each member (everything except functions/methods and rules) of the module that you want to document. For functions and object methods, call **(3)** `DOC_RECORDER.add_function_doc(...)`. For Snakamake rules, call **(4)** `DOC_RECORDER.add_rule_doc(...)`.The documentation is dumped as a Markdown file and thus supports (basic) Markdown syntax for emphasis etc. In order to generate the documentation, execute the workflow with the target rule `run_build_docs`.
3. DocContext
    - datatype: <class 'enum.EnumType'>
    - documentation: Enum listing the different documentation contexts. The context is used to sort the dumped documentation Markdown file into `docs/<context>/autodoc.md`. The currently supported contexts are: **(1) TEMPLATE**: The TEMPLATE context must only be used to document code of the workflow template. **(2) WORKFLOW**: The WORKFLOW context must only be used to document workflow code outside of the template modules rules, functions, variables etc.
4. DocLevel
    - datatype: <class 'enum.EnumType'>
    - documentation: Enum listing the different documentation levels such as USERCONFIG and GLOBALVAR that need to be specified when documenting module 'members', 'rules', 'functions' and so on. See documentation of the DOC_RECORDER object for more details. The currently supported levels are: **(1) USERCONFIG**: Use this level to document (non-template) workflow parameters that can be configured by end users, e.g., by adding a YAML config file via `--configfiles` to the Snakemake run. **(2) TARGETRULE**: This is an implicit DocLevel that is automatically set when documenting a rule via `DOCREC.add_rule_doc(...)`. Do not use this level in any other way. This level indicates recommended Snakemake rules to be used as execution targets, including generic rules such as `run_all`. **(3) GLOBALVAR**: Use this level to document globally accessible variables; this also includes many variables initiated as part of the workflow template. Workflow developers must rely on the global template variables when implementing a new workflow. **(4) GLOBALFUN**: This is an implicit DocLevel that is automatically set when documenting a [Python] function via `DOCREC.add_function_doc(...)`. Do not use this level in any other way. This level indicates a globally accessible [Python] function, including utility-style functions shipped with the template. **(5) GLOBALOBJ**: Use this level to document globally available [Python] objects that offer specific funtionality. The most useful example for this is the `DOCREC` (DocRecorder) object that must be used to document other workflow components in place. **(6) OBJMETHOD**: This is an implicit DocLevel that is automatically set when documenting a [Python] function via `DOCREC.add_function_doc(...)`. Do not use this level in any other way. This level indicates an object method, e.g., the `DOCREC.add_function_doc(...)` or `DOCREC.add_rule_doc(...)` methods fall under this documentation level. **(7) DEVONLY**: Use this level to document 'things' in the workflow that a regular user does not need to understand, but developers must pay attention to.

### Documentation level: OBJMETHOD

1. add_function_doc
    - datatype: <class 'DocRecorder'>.<class 'method'>
    - documentation: 
```
    This function of the DocRecorder class / DOCREC instance
must be called to document either module-level / global
functions or class methods. In case of class methods,
the documentation level is set to DocLevel.OBJMETHOD and to
DocLevel.GLOBALFUN otherwise.

Args:
    function (callable): function/method to document
    parent (None or class): parent class if class method

Returns:
    None
```
2. add_member_doc
    - datatype: <class 'DocRecorder'>.<class 'method'>
    - documentation: 
```
    This function of the DocRecorder class / DOCREC instance
must be called to document module-level members, i.e. global
variables, functions, objects, user configurables and
developer-only information.

Args:
    doc_level (DocLevel): the documentation level
    name (str): name of the documented thing
    thing (any): the documented thing (i.e., some Python object)
    documentation (str): the documentation for thing

Returns:
    None

Raises:
    ValueError: if doc_level in [
    DocLevel.OBJMETHOD
    DocLevel.GLOBALFUN
    DocLevel.TARGETRULE
    ]
```
3. add_module_doc
    - datatype: <class 'DocRecorder'>.<class 'method'>
    - documentation: 
```
    This member function must be called at the beginning
of each new module to record the documentation
in the correct module file context.

Args:
    doc_context (DocContext): documentation context enum type
    module_name (str or list of str): name of the module given as relative path

Returns:
    None
```
4. add_rule_doc
    - datatype: <class 'DocRecorder'>.<class 'method'>
    - documentation: 
```
    This function of the DocRecorder class / DOCREC instance
must be called to document Snakemake rules that represent
reasonable execution targets from the user perspective.
Canonically, this applies to all rules in the main
Snakefile and potentially also to aggregation-style
rules at the end of individual workflow modules.

Important: when running 'snakefmt', the keyword 'rule'
is problematic depending on where exactly in a line it
appears (e.g., below, it would be at the beginning of the line).
Hence, renamed the variable to 'smk_rule'.

Args:
    smk_rule (snakemake.rules.Rule): rule to document

Returns:
    None
```

## Module: commons::10-constants::00_legacy.smk

**Module file**: `workflow/rules/commons/10-constants/00_legacy.smk`

### Documentation level: DEVONLY

1. SNAKEMAKE_LEGACY_RUN
    - datatype: <class 'bool'>
    - documentation: This variable can be checked if it is critical to determine whether or not the workflow is executed with a Snakemake legacy version (typically v7) or with a more recent release (typically v9+).

## Module: commons::30-settings::00-infrastructure::00_hardware.smk

**Module file**: `workflow/rules/commons/30-settings/00-infrastructure/00_hardware.smk`

### Documentation level: USERCONFIG

1. CPU_HIGH
    - datatype: <class 'int'>
    - documentation: The number of CPU cores/threads to use for rules benefitting from high parallelization. Typical values are in the range of 16 to 24. See the help for CPU_LOW for more details.
2. CPU_LOW
    - datatype: <class 'int'>
    - documentation: The number of CPU cores/threads to use for rules benefitting from limited parallelization. Typical values are in the range of 2 to 6. Workflow developers refer to this value in the `threads:` directive of the relevant rules. Users can dynamically change this value via the command line, i.e. by setting --config cpu_low=N or by adding the entry `cpu_low: N` to any of the Snakemake YAML configuration files read via `--configfiles`.
3. CPU_MAX
    - datatype: <class 'int'>
    - documentation: The number of CPU cores/threads to use for rules benefitting from maximal parallelization. Typical values are in the range of 48 to 128. Note that this value must not be higher than the CPU limit of the infrastructure the workflow is running on. See the help for CPU_LOW for more details.
4. CPU_MEDIUM|CPU_MED
    - datatype: <class 'int'>
    - documentation: The number of CPU cores/threads to use for rules benefitting from modest parallelization. Typical values are in the range of 8 to 12. See the help for CPU_LOW for more details.

## Module: commons::30-settings::00-infrastructure::10_software.smk

**Module file**: `workflow/rules/commons/30-settings/00-infrastructure/10_software.smk`

### Documentation level: DEVONLY

1. ENV_MODULE_APPTAINER
    - datatype: <class 'str'>
    - documentation: The name of the env(ironment) module that loads the Apptainer executable into `$PATH`. This is typically only relevant in HPC environments. Apptainer is the successor of Singularity and needed to execute containerized tools. The template uses this variable if CUBI-style reference containers are used.
2. ENV_MODULE_SINGULARITY
    - datatype: <class 'str'>
    - documentation: The name of the env(ironment) module that loads the Singularity executable into `$PATH`. This is typically only relevant in HPC environments. Note that Singularity is deprecated and has been replaced by Apptainer. The template uses this variable if CUBI-style reference containers are used.

## Module: commons::30-settings::10-runtime::00_snakemake.smk

**Module file**: `workflow/rules/commons/30-settings/10-runtime/00_snakemake.smk`

### Documentation level: GLOBALVAR

1. DEBUG
    - datatype: <class 'bool'>
    - documentation: Represents the info if the workflow is executed via `snakemake --debug [...]`, which allows to set breakpoints in `run:` blocks.
2. DRYRUN
    - datatype: <class 'bool'>
    - documentation: Represents the info if the workflow is executed via `snakemake --dryrun [...]`.
3. VERBOSE
    - datatype: <class 'bool'>
    - documentation: Represents the info if the workflow is executed via `snakemake --verbose [...]`, i.e. Snakemake is printing verbose/debugging output.

### Documentation level: DEVONLY

1. RUN_IN_DEV_MODE
    - datatype: <class 'bool'>
    - documentation: Represents the info if the workflow is executed via `snakemake --config devmode=True [...]`
2. RUN_IN_TEST_MODE
    - datatype: <class 'bool'>
    - documentation: Represents the info if the workflow is executed via `snakemake [...] run_tests` or `snakemake [...] run_tests_no_manifest`.
3. USE_APPTAINER
    - datatype: <class 'bool'>
    - documentation: Represents the info if the workflow uses Apptainer (Singularity) for software deployment.
4. USE_CONDA
    - datatype: <class 'bool'>
    - documentation: Represents the info if the workflow uses Conda for software deployment.
5. USE_ENV_MODULES
    - datatype: <class 'bool'>
    - documentation: Represents the info if the workflow uses '(environment) modules' for software deployment. This typically only applies to HPC infrastructures.
6. USE_SINGULARITY
    - datatype: <class 'bool'>
    - documentation: Represents the info if the workflow uses Singularity (Apptainer) for software deployment.

## Module: commons::30-settings::20-environment::05_paths.smk

**Module file**: `workflow/rules/commons/30-settings/20-environment/05_paths.smk`

### Documentation level: GLOBALVAR

1. DIR_BENCHMARK
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: Relative path pointing to `rsrc` in the `WORKDIR`. Alias for DIR_RSRC.
2. DIR_CLUSTERLOG_ERR
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: Relative path pointing to `log/cluster_jobs/err` in the `WORKDIR`. Only relevant in HPC environments. Intended to capture all stderr streams of executed rules/jobs (if applicable).
3. DIR_CLUSTERLOG_OUT
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: Relative path pointing to `log/cluster_jobs/out` in the `WORKDIR`. Only relevant in HPC environments. Intended to capture all stdout streams of executed rules/jobs (if applicable).
4. DIR_ENVS
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: Fully resolved directory path to `[..]/workflow/envs`. Any Conda environment yaml file used by the workflow can thus be addressed via `DIR_ENVS.joinpath(...)`.
5. DIR_GLOBAL_REF
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: Relative path pointing to `global_ref` in the `WORKDIR`. This default directory is the source location for all reference data files that are *not* being produced by the workflow itself.
6. DIR_LOCAL_REF
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: Relative path pointing to `local_ref` in the `WORKDIR`. This default directory is the target and source location for all reference data files that are produced programmatically by the workflow itself. In other words, for each file in `local_ref`, there must be a rule in the workflow that produces that file.
7. DIR_LOG
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: Relative path pointing to `log` in the `WORKDIR`. All log files of the workflow can be addressed via `DIR_LOG.joinpath(...)` in Snakemake rules.
8. DIR_PROC
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: Relative path pointing to `proc` in the `WORKDIR`. All non-result files of the workflow can be addressed via `DIR_PROC.joinpath(...)` in Snakemake rules.
9. DIR_REPO
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: Recommended alias/shorthand for `DIR_REPOSITORY`, i.e. the fully resolved directory path to the workflow repository. By convention, this is always taken to be the parent of the `workflow/` directory. CAVEAT: typically, this path will correspond to the top-level folder of the repository ('the git root') but this is not checked.
10. DIR_RES
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: Relative path pointing to `results` in the `WORKDIR`. All result files of the workflow can be addressed via `DIR_RES.joinpath(...)` in Snakemake rules.
11. DIR_RSRC
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: Relative path pointing to `rsrc` in the `WORKDIR`. All resource ('benchmark') files of the workflow can be addressed via `DIR_LOG.joinpath(...)` in Snakemake rules.
12. DIR_SCRIPTS
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: Fully resolved directory path to `[..]/workflow/scripts`. Any script used by the workflow can thus be addressed via `DIR_SCRIPTS.joinpath(...)`. See also the `get_script` function.
13. DIR_SNAKEFILE
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: Fully resolved directory path in which the workflow's main snakefile resides. By convention, this path always ends with the last component `workflow/`.
14. DIR_WORKING
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: Recommended global variable representing the fully resolved path to the Snakemake working directory, i.e. the content of the `--directory` / `-d` command line parameter. **CAUTION**: this parameter should only be used if absolutely necessary. All relevant directory paths should be addressed via the other global variables of this module.
15. NAME_SNAKEFILE
    - datatype: <class 'str'>
    - documentation: Name of the workflow's main snakefile, which is always `Snakefile` by convention / best practices.
16. PATH_SNAKEFILE
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: Fully resolved file path of the workflow's main snakefile.
17. WORKDIR
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: Alias/shorthand for `DIR_WORKING`.

### Documentation level: DEVONLY

1. WD_PATHS_MUST_RESOLVE
    - datatype: <class 'bool'>
    - documentation: If the workflow is executed with `--config devmode=True`, non-existing default paths are ignored and do not raise an error.

## Module: commons::30-settings::20-environment::10_file_constants.smk

**Module file**: `workflow/rules/commons/30-settings/20-environment/10_file_constants.smk`

### Documentation level: USERCONFIG

1. RUN_SUFFIX
    - datatype: <class 'str'>
    - documentation: You can set a 'suffix' string for this run that will be appended to the run manifest file and the copy of the sample sheet (if applicable): `snakemake [...] --config suffix=yoursuffix` This enables you, e.g., to distinguish between different sample sets that you process in the same workflow directory. The default value 'derive' triggers a dynamic suffix derived from the file name of the sample sheet if used or is empty otherwise. The run suffix must only contain lower case letters a-z, number 0-9 and the hyphen/minus '-' sign.

### Documentation level: DEVONLY

1. MANIFEST_RELPATH
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: Relative path to the workflow manifest file that is created in the results folder. This is only used as a trigger file in the rules of the main Snakefile.
2. RUN_CONFIG_RELPATH
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: Relative path to the copy of the workflow configuration YAML that is placed in the results folder. This is only used as a trigger file in the rules of the main Snakefile.

## Module: commons::30-settings::20-environment::20_accounting.smk

**Module file**: `workflow/rules/commons/30-settings/20-environment/20_accounting.smk`

### Documentation level: USERCONFIG

1. RESET_ACCOUNTING
    - datatype: <class 'bool'>
    - documentation: If the workflow can no longer be executed because the file accounting information creates a deadlock (see `docs/template/accounting.md` for details), you can erase the accounting metadata by setting the command line switch `--config resetacc=True`. Workflow developers typically do not need to access this variable.

### Documentation level: DEVONLY

1. ACCOUNTING_FILES
    - datatype: <class 'dict'>
    - documentation: A look-up data structure that enables name-based access to the three different accounting files capturing input, reference and result file metadata. This is DEPRECATED and should be turned into global variables as part of the template file constants module. See gh#52

## Module: commons::30-settings::20-environment::30_ref_container.smk

**Module file**: `workflow/rules/commons/30-settings/20-environment/30_ref_container.smk`

### Documentation level: USERCONFIG

1. DIR_REFCON
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: Shorthand for 'DIR_REFERENCE_CONTAINER' - only available in the workflow context at runtime. See documentation for 'DIR_REFERENCE_CONTAINER' for details.
2. DIR_REFERENCE_CONTAINER
    - datatype: <class 'pathlib._local.PosixPath'>
    - documentation: The path on the file system (accessible at workflow runtime) that contains the reference containers (*.sif files). Setting the option 'reference_container_store' to a non-empty value is required if 'use_reference_container' is set to 'true'.
3. USE_REFCON
    - datatype: <class 'bool'>
    - documentation: Shorthand for 'USE_REFERENCE_CONTAINER' - only available in the workflow context at runtime. See documentation for 'USE_REFERENCE_CONTAINER' for details.
4. USE_REFERENCE_CONTAINER
    - datatype: <class 'bool'>
    - documentation: Using CUBI-style reference containers in this workflow requires setting the parameter 'use_reference_container: true' in a loaded config YAML file or on the command line via --config use_reference_container=true. This user setting is stored in the global variable USE_REFERENCE_CONTAINER in the workflow context at runtime. Note to users: setting this option to 'true' implies that the options 'reference_container_store' and 'reference_container_names' must be non-empty.

### Documentation level: DEVONLY

1. DIR_REFCON_CACHE
    - datatype: <class 'NoneType'>
    - documentation: The path in the Snakemake working directory hierarchy that contains the manifest cache for all reference containers.

## Module: commons::40-pyutils::05_simple_get.smk

**Module file**: `workflow/rules/commons/40-pyutils/05_simple_get.smk`

### Documentation level: GLOBALFUN

1. find_script
    - datatype: <class 'function'>
    - documentation: 
```
    Original version of 'get_script'.

DEPRECATED FUNCTION --- see 'get_script'
```
2. get_hostname
    - datatype: <class 'function'>
    - documentation: 
```
    Returns:
    host (str): name of host machine
```
3. get_script
    - datatype: <class 'function'>
    - documentation: 
```
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
```
4. get_timestamp
    - datatype: <class 'function'>
    - documentation: 
```
    Get naive (not timezone-aware)
timestamp representing 'now'.
The formatting is following
ISO 8601 w/o timezone offset, i.e.
YYYY-MM-DDThh-mm-ss
(24-hour format for time)

Returns:
    ts (str): timestamp of 'now' w/o tz
```
5. get_username
    - datatype: <class 'function'>
    - documentation: 
```
    Returns:
    user (str): login name of current user
```

## Module: commons::40-pyutils::15_simple_logging.smk

**Module file**: `workflow/rules/commons/40-pyutils/15_simple_logging.smk`

### Documentation level: GLOBALFUN

1. log_err
    - datatype: <class 'function'>
    - documentation: 
```
    Alias for 'loggerr'
```
2. log_out
    - datatype: <class 'function'>
    - documentation: 
```
    Alias for 'logout'
```
3. logerr
    - datatype: <class 'function'>
    - documentation: 
```
    Log a message to sys.stderr.
If VERBOSE is set, the level is
set to 'VERBOSE (err/dbg)' and to
'ERROR' otherwise. The message is
prefixed with the current timestamp.

Args:
    msg (str): message text

Returns:
    None
```
4. logout
    - datatype: <class 'function'>
    - documentation: 
```
    Log a message to sys.stdout with level
INFO. The message is prefixed with
the current timestamp.

Args:
    msg (str): message text

Returns:
    None
```
5. write_log_message
    - datatype: <class 'function'>
    - documentation: 
```
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
```

## Module: commons::40-pyutils::20_simple_fs.smk

**Module file**: `workflow/rules/commons/40-pyutils/20_simple_fs.smk`

### Documentation level: GLOBALFUN

1. rsync_f2d
    - datatype: <class 'function'>
    - documentation: 
```
    Convenience function to 'rsync' a source
file into a target directory (file name
not changed) in a 'run' block of a
Snakemake rule. Creates necessary
subdirectories for target.

Args:
    source_file (str | pathlib.Path): the source file path
    target_dir (str | pathlib.Path): the target directory

Returns:
    None
```
2. rsync_f2f
    - datatype: <class 'function'>
    - documentation: 
```
    Convenience function to 'rsync' a source
file to a target location (copy file
and change name) in a 'run' block of
a Snakemake rule. Creates necessary
subdirectories for target.

Args:
    source_file (str | pathlib.Path): the source file path
    target_file (str | pathlib.Path): the target file path

Returns:
    None
```

## Module: commons::40-pyutils::40_sample_sheet.smk

**Module file**: `workflow/rules/commons/40-pyutils/40_sample_sheet.smk`

### Documentation level: GLOBALFUN

1. read_sample_sheet
    - datatype: <class 'function'>
    - documentation: 
```
    This function reads a TSV text file that is assumed
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
```

## Module: commons::40-pyutils::80_template_refcon.smk

**Module file**: `workflow/rules/commons/40-pyutils/80_template_refcon.smk`

### Documentation level: GLOBALFUN

1. refcon_find_container
    - datatype: <class 'function'>
    - documentation: 
```
    Given the requested ref_filename as input,
find the matching reference container that can provide
this file. Throws for ambiguous or no matchings.

TODO: adapt this function to also work in a lenient
mode that simply checks if the requested file already
exists in GLOBAL_REF and then returns False to sidestep
a forced data loading from a container (accept that the
user manually copies a reference file into the global
reference folder).

Args:
    manifest_cache (pathlib.Path): path to reference container manifest cache file
    ref_filename (str): the name of the reference file we are looking for

Returns:
    pathlib.Path: the path to the reference container holding the reference file
```
2. refcon_find_container
    - datatype: <class 'function'>
    - documentation: 
```
    Given the requested ref_filename as input,
find the matching reference container that can provide
this file. Throws for ambiguous or no matchings.

TODO: adapt this function to also work in a lenient
mode that simply checks if the requested file already
exists in GLOBAL_REF and then returns False to sidestep
a forced data loading from a container (accept that the
user manually copies a reference file into the global
reference folder).

Args:
    manifest_cache (pathlib.Path): path to reference container manifest cache file
    ref_filename (str): the name of the reference file we are looking for

Returns:
    pathlib.Path: the path to the reference container holding the reference file
```
3. trigger_refcon_manifest_caching
    - datatype: <class 'function'>
    - documentation: 
```
    This function merely triggers the checkpoint
to merge all reference containers caches into
one. This checkpoint is needed to get a
start-to-end run, otherwise "refcon_find_container"
would produce an error.

Args:
    wildcards (dict): the Snakemake wildcards object

Returns:
    pathlib.Path: the path to the reference container manifest cache file
```

## Module: commons::40-pyutils::85_template_accounting.smk

**Module file**: `workflow/rules/commons/40-pyutils/85_template_accounting.smk`

### Documentation level: GLOBALFUN

1. _load_data_line
    - datatype: <class 'function'>
    - documentation: 
```
    Simple utility function that reads the file metadata
(= file size or checksums) from the respective files
on disk.

Args:
    file_path: path to metadata file, i.e. *.md5 / *.bytes / *.sha256
Returns:
    str: the respective metadata value, i.e. a checksum or file size
```
2. load_accounting_information
    - datatype: <class 'function'>
    - documentation: 
```
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
```
3. load_file_by_path_id
    - datatype: <class 'function'>
    - documentation: 
```
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
```
4. process_accounting_record
    - datatype: <class 'function'>
    - documentation: 
```
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
```
5. register_input
    - datatype: <class 'function'>
    - documentation: 
```
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
```
6. register_reference
    - datatype: <class 'function'>
    - documentation: 
```
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
```
7. register_result
    - datatype: <class 'function'>
    - documentation: 
```
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
```

## Module: commons::40-pyutils::90_template_staging.smk

**Module file**: `workflow/rules/commons/40-pyutils/90_template_staging.smk`

### Documentation level: GLOBALFUN

1. _reset_file_accounts
    - datatype: <class 'function'>
    - documentation: 
```
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
```

