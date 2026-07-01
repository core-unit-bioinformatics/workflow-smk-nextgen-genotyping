"""
Use this module to list all includes
required for your pipeline - do not
add your pipeline-specific modules
to "commons/00_commons.smk"
"""

include: "15-init/05_tools.smk"
include: "15-init/10_references.smk"
include: "15-init/20_sample_sheet.smk"

include: "20-prepare/00_pyutils.smk"
include: "20-prepare/10_references.smk"
include: "20-prepare/20_inputs.smk"

if RUN_PANGENIE:
    include: "30-genotyping/10_pangenie.smk"

if RUN_LOCITYPER:
    include: "30-genotyping/20_locityper.smk"