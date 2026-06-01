"""Module containing global infrastructure
settings pertaining to the software
environment that is assumed to be under
the control of an IT department / the local
system administrators (= on managed infrastructure).
Typically, the parameters in this module only
need a non-default configuration if the
system-wide software configuration is not
fully supporting all features regarding,
e.g., software deployment that Snakemake
has built-in.
"""

_THIS_MODULE = ["commons", "30-settings", "00-infrastructure", "10_software.smk"]
_THIS_CONTEXT = DocContext.TEMPLATE

DOCREC.add_module_doc(_THIS_CONTEXT, _THIS_MODULE)

# needed if Singularity/Apptainer is not
# in $PATH by default on a managed system.
ENV_MODULE_SINGULARITY = config.get(
    OPTIONS.env_singularity.name, OPTIONS.env_singularity.default
)

DOCREC.add_member_doc(
    DocLevel.DEVONLY,
    "ENV_MODULE_SINGULARITY",
    ENV_MODULE_SINGULARITY,
    (
        "The name of the env(ironment) module that loads "
        "the Singularity executable into `$PATH`. This is "
        "typically only relevant in HPC environments. Note "
        "that Singularity is deprecated and has been replaced "
        "by Apptainer. "
        "The template uses this variable if CUBI-style "
        "reference containers are used."
    ),
)

# this is to prep dropping Singularity support;
# expectation is the switch from Singularity to Apptainer
# takes some time on managed infrastructure for reasons
# of backwards compatibility
ENV_MODULE_APPTAINER = config.get(
    OPTIONS.env_singularity.name, OPTIONS.env_singularity.default
)

DOCREC.add_member_doc(
    DocLevel.DEVONLY,
    "ENV_MODULE_APPTAINER",
    ENV_MODULE_APPTAINER,
    (
        "The name of the env(ironment) module that loads "
        "the Apptainer executable into `$PATH`. This is "
        "typically only relevant in HPC environments. "
        "Apptainer is the successor of Singularity "
        "and needed to execute containerized tools. "
        "The template uses this variable if CUBI-style "
        "reference containers are used."
    ),
)
