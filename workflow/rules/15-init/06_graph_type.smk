"""
Determine which loci-database construction route locityper should
use:
    "vcf" (default) - build directly from the pangenome graph VCF,
                       as before.
    "agc"            - build via extract-targets.sh, mapping loci
                       coordinates against a set of HPRC assemblies
                       in an AGC archive, instead of the graph VCF.

Controlled via the optional 'graph_type' config parameter, e.g.:
    snakemake [...] --config graph_type=agc
Only relevant when locityper is selected via 'tools' - harmless
(parsed but unused) otherwise.
"""

_AVAILABLE_GRAPH_TYPES = {"vcf", "agc"}

LOCITYPER_GRAPH_TYPE = str(config.get("graph_type", "vcf")).strip().lower()

if LOCITYPER_GRAPH_TYPE not in _AVAILABLE_GRAPH_TYPES:
    err_msg = (
        f"Error: unknown 'graph_type' value '{LOCITYPER_GRAPH_TYPE}' - "
        f"must be one of {sorted(_AVAILABLE_GRAPH_TYPES)}."
    )
    logerr(err_msg)
    raise ValueError(err_msg)

logout(f"Locityper graph-type: {LOCITYPER_GRAPH_TYPE}")
