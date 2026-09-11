import enum
import collections
import pathlib


class ReferenceTypes(enum.Enum):
    LINEAR_REFERENCE_GENOME = 0
    GENOME = 0
    PANGENOME_REFERENCE_GRAPH = 1
    PANGENOME = 1
    REFERENCE_CALLSET = 2
    CALLSET = 2
    LOCI_CATALOG = 3
    HPRC_ASSEMBLIES = 4
    ASSEMBLY_ALIASES = 5


REFERENCE_WILDCARD_LOOKUP = collections.defaultdict(list)
REFERENCE_FILE_LOOKUP = collections.defaultdict(dict)


def _pangenome_graph_required():
    # needed by pangenie always, and by locityper only when building
    # its loci database from the graph VCF route (not the AGC route) -
    return "pangenie" in TOOLS_LIST or ("locityper" in TOOLS_LIST and LOCITYPER_GRAPH_TYPE == "vcf")


def _agc_assemblies_required():
    return "locityper" in TOOLS_LIST and LOCITYPER_GRAPH_TYPE == "agc"


# reference types that are only required under certain conditions
# (which tool(s) are selected via 'tools', and for locityper, which
# loci-database route is selected via 'graph_type'). Skip validation
# (and the requirement to have the config key present) if the
# corresponding predicate returns False.
_REFERENCE_TYPE_REQUIRED_PREDICATES = {
    ReferenceTypes.PANGENOME_REFERENCE_GRAPH: _pangenome_graph_required,
    ReferenceTypes.REFERENCE_CALLSET: lambda: "pangenie" in TOOLS_LIST,
    ReferenceTypes.LOCI_CATALOG: lambda: "locityper" in TOOLS_LIST,
    ReferenceTypes.HPRC_ASSEMBLIES: _agc_assemblies_required,
    ReferenceTypes.ASSEMBLY_ALIASES: _agc_assemblies_required,
}

for member in ReferenceTypes:
    is_required = _REFERENCE_TYPE_REQUIRED_PREDICATES.get(member)
    if is_required is not None and not is_required():
        continue

    config_key = member.name.lower()
    configured_reference = config[config_key]
    ref_name = configured_reference["label"]
    if not ref_name.isalnum():
        err_msg = (
            f"Invalid reference label: {ref_name} - "
            "Please use only alphanumeric (a-z, 0-9) characters "
            "(case is ignored)."
        )
        logerr(err_msg)
        raise ValueError(err_msg)

    ref_file_path = pathlib.Path(configured_reference["path"])
    if not ref_file_path.is_file():
        err_msg = f"Configured reference file is not accessible: {ref_name} / {ref_file_path}"
        logerr(err_msg)
        raise FileNotFoundError(err_msg)
    REFERENCE_WILDCARD_LOOKUP[member].append(ref_name)
    REFERENCE_FILE_LOOKUP[member][ref_name] = ref_file_path