"""
Determine the maximum amount of temp disk space (in MB) the workflow
is allowed to reserve at any one time for temp() outputs produced by
PanGenie and locityper. Three values are set here:

  _MAX_TEMP_DISK_MB     - the global 'disk_mb' resource pool ceiling,
                           registered with Snakemake's scheduler.
  MAX_TEMP_PANGENIE_MB  - disk_mb declared on PanGenie's temp-producing
                           ('run_pangenie_genotyping') and temp-consuming
                           ('convert_pangenie_genotypes_to_biallelic') rules.
  MAX_TEMP_LOCITYPER_MB - disk_mb declared on locityper's temp-producing
                           ('concatenate_locityper_multi_reads',
                           'concatenate_locityper_paired_multi_reads') and
                           temp-consuming ('preprocess_locityper_reads') rules.

Controlled via the optional config parameters below, e.g.:
    snakemake [...] --config max_temp_disk_mb=700000 max_temp_pangenie_mb=40000 max_temp_locityper_mb=100000
Defaults (if not set):
    max_temp_disk_mb:      700000 (~700GB) - covers ~5 concurrent samples
    max_temp_pangenie_mb:   40000 (~40GB)  - PanGenie's temp VCF
    max_temp_locityper_mb: 100000 (~100GB) - locityper's concatenated FASTQ

If '--resources disk_mb=...' is also passed explicitly on the CLI (or
set via profile), that value takes precedence over max_temp_disk_mb.

Size the per-tool values to your own data - measure actual temp file
sizes for a few representative samples and add a safety margin.
"""

_TEMP_BUDGET_DEFAULTS = {
    "max_temp_disk_mb": 700_000,
    "max_temp_pangenie_mb": 40_000,
    "max_temp_locityper_mb": 100_000,
}


def _parse_temp_budget_mb(param_name):
    default = _TEMP_BUDGET_DEFAULTS[param_name]
    if param_name not in config or not str(config[param_name]).strip():
        logout(
            f"No '{param_name}' parameter was provided on the command line "
            f"(--config {param_name}=...) or in the config file. Defaulting to "
            f"{default} MB (~{default // 1000}GB)."
        )
        value = default
    else:
        try:
            value = int(config[param_name])
        except (TypeError, ValueError):
            err_msg = (
                f"Error: '{param_name}' must be an integer (MB), got "
                f"'{config[param_name]}'."
            )
            logerr(err_msg)
            raise ValueError(err_msg)
        logout(
            f"Temp disk budget requested for this run (via config) - "
            f"{param_name}: {value} MB (~{value // 1000}GB)"
        )

    if value <= 0:
        err_msg = f"Error: '{param_name}' must be a positive integer, got {value}."
        logerr(err_msg)
        raise ValueError(err_msg)
    return value


_MAX_TEMP_DISK_MB = _parse_temp_budget_mb("max_temp_disk_mb")
MAX_TEMP_PANGENIE_MB = _parse_temp_budget_mb("max_temp_pangenie_mb")
MAX_TEMP_LOCITYPER_MB = _parse_temp_budget_mb("max_temp_locityper_mb")

for _tool_name, _tool_mb in (("pangenie", MAX_TEMP_PANGENIE_MB), ("locityper", MAX_TEMP_LOCITYPER_MB)):
    if _tool_mb > _MAX_TEMP_DISK_MB:
        err_msg = (
            f"Error: 'max_temp_{_tool_name}_mb' ({_tool_mb} MB) exceeds "
            f"'max_temp_disk_mb' ({_MAX_TEMP_DISK_MB} MB) - no single "
            f"{_tool_name} job could ever be scheduled under this budget."
        )
        logerr(err_msg)
        raise ValueError(err_msg)

workflow.global_resources.setdefault("disk_mb", _MAX_TEMP_DISK_MB)