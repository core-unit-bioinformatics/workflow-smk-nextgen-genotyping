"""Module containing global infrastructure
limits for CPU (cores) and memory that must
be respected by all jobs send to a (cluster)
scheduler. Compliance must be checked in the
calling scope, i.e., typically in the resources
section of a snakemake rule.
"""

_THIS_MODULE = ["commons", "30-settings", "00-infrastructure", "00_hardware.smk"]
_THIS_CONTEXT = DocContext.TEMPLATE

DOCREC.add_module_doc(_THIS_CONTEXT, _THIS_MODULE)


# CPU limits
CPU_LOW = config.get(OPTIONS.cpu_low.name, OPTIONS.cpu_low.default)
assert isinstance(CPU_LOW, int)

DOCREC.add_member_doc(
    DocLevel.USERCONFIG,
    "CPU_LOW",
    CPU_LOW,
    (
        "The number of CPU cores/threads to use for rules "
        "benefitting from limited parallelization. Typical "
        "values are in the range of 2 to 6. Workflow developers "
        "refer to this value in the `threads:` directive "
        "of the relevant rules. Users can dynamically "
        "change this value via the command line, i.e. "
        "by setting --config cpu_low=N or by adding the "
        "entry `cpu_low: N` to any of the Snakemake YAML "
        "configuration files read via `--configfiles`."
    ),
)


CPU_MEDIUM = config.get(OPTIONS.cpu_medium.name, OPTIONS.cpu_medium.default)
CPU_MED = CPU_MEDIUM
assert isinstance(CPU_MEDIUM, int)

DOCREC.add_member_doc(
    DocLevel.USERCONFIG,
    "CPU_MEDIUM|CPU_MED",
    CPU_MEDIUM,
    (
        "The number of CPU cores/threads to use for rules "
        "benefitting from modest parallelization. Typical values "
        "are in the range of 8 to 12. See the help for CPU_LOW "
        "for more details."
    ),
)


CPU_HIGH = config.get(OPTIONS.cpu_high.name, OPTIONS.cpu_high.default)
assert isinstance(CPU_HIGH, int)

DOCREC.add_member_doc(
    DocLevel.USERCONFIG,
    "CPU_HIGH",
    CPU_HIGH,
    (
        "The number of CPU cores/threads to use for rules "
        "benefitting from high parallelization. Typical values "
        "are in the range of 16 to 24. See the help for CPU_LOW "
        "for more details."
    ),
)


CPU_MAX = config.get(OPTIONS.cpu_max.name, OPTIONS.cpu_max.default)
assert isinstance(CPU_MAX, int)

DOCREC.add_member_doc(
    DocLevel.USERCONFIG,
    "CPU_MAX",
    CPU_MAX,
    (
        "The number of CPU cores/threads to use for rules "
        "benefitting from maximal parallelization. Typical values "
        "are in the range of 48 to 128. "
        "Note that this value must not be higher than "
        "the CPU limit of the infrastructure the workflow is "
        "running on. See the help for CPU_LOW for more details."
    ),
)

# Memory limits
# First, the actual variables are set to None
# to indicate that the config info still needs
# to be parsed and turned into an integer.
# Reasoning:
# This is a design decision because the config
# settings here should be simple, i.e., consist
# essentially of value assignments. Parsing the
# potential suffix and converting the string into
# the appropriately scaled number/integer requires
# more complex logic that is implemented in the
# pyutils branch of the 'commons' modules. The pyutils
# will only be included later because they have
# many more dependencies to the parameters
# specified in the 'settings' branch. Hence, it is
# not reasonable to first include pyutils and then
# settings to realize the parsing/conversion right here.
MEM_MAX = None
MEM_COMMON = None

_MEM_MAX_CONFIG = config.get(OPTIONS.mem_max.name, OPTIONS.mem_max.default)

_MEM_COMMON_CONFIG = config.get(OPTIONS.mem_common.name, OPTIONS.mem_common.default)
