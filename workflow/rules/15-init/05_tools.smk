"""
Determine which tool(s) of the pipeline should be executed
for this run. Controlled via the mandatory 'tools' config
parameter, e.g.:
    snakemake [...] --config tools=pangenie,locityper
Available tools: pangenie, locityper
"""

_AVAILABLE_TOOLS = {"pangenie", "locityper"}

if "tools" not in config or not str(config["tools"]).strip():
    err_msg = (
        "Error: no tools specified to run. Please provide "
        "'--config tools=<comma-separated list>' "
        f"(available: {sorted(_AVAILABLE_TOOLS)})."
    )
    logerr(err_msg)
    raise ValueError(err_msg)

TOOLS_LIST = sorted(set(
    t.strip().lower() for t in str(config["tools"]).split(",") if t.strip()
))

_invalid_tools = set(TOOLS_LIST) - _AVAILABLE_TOOLS
if _invalid_tools:
    err_msg = (
        f"Error: unknown tool(s) requested via 'tools' parameter: {sorted(_invalid_tools)}. "
        f"Available: {sorted(_AVAILABLE_TOOLS)}"
    )
    logerr(err_msg)
    raise ValueError(err_msg)

if not TOOLS_LIST:
    err_msg = "Error: 'tools' parameter resolved to an empty list."
    logerr(err_msg)
    raise ValueError(err_msg)

RUN_PANGENIE = "pangenie" in TOOLS_LIST
RUN_LOCITYPER = "locityper" in TOOLS_LIST
