# Diagnostic plots of the PanGenie genotypes (written to results/plots/):
# - HWE plots (heterozygosity vs. allele frequency)
# - allele frequency in the cohort vs. in the reference panel
# - number of SVs per sample
# Each plot is written as PNG and PDF. The HWE and AF plots exist for all variants
# and separately for SNVs, indels and SVs.

PLOT_VARIANT_CLASSES = ["all", "snv", "indel", "sv"]


rule plot_pangenie_hwe:
    """
    HWE plots: fraction of heterozygous genotypes vs. allele frequency of each variant
    in the cohort, together with the expectation 2p(1-p) under Hardy-Weinberg equilibrium.
    """
    input:
        cohort = rules.tabulate_pangenie_cohort_variants.output.tsv
    output:
        png = expand(
            DIR_RES.joinpath("plots", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.pg-hwe.{variant_class}.png"),
            variant_class=PLOT_VARIANT_CLASSES,
            allow_missing=True
        ),
        pdf = expand(
            DIR_RES.joinpath("plots", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.pg-hwe.{variant_class}.pdf"),
            variant_class=PLOT_VARIANT_CLASSES,
            allow_missing=True
        )
    log:
        DIR_LOG.joinpath("50-plotting", "20_plots", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.pg-hwe.log")
    benchmark:
        DIR_RSRC.joinpath("50-plotting", "20_plots", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.pg-hwe.rsrc")
    conda:
        DIR_ENVS.joinpath("plotting.yaml")
    threads: CPU_LOW
    resources:
        mem_mb=lambda wildcards, attempt: (16 * 1024) * attempt,
        time_hrs=lambda wildcards, attempt: 2 * attempt
    params:
        script = get_script("plot_hwe.py"),
        out_prefix = lambda wildcards: DIR_RES.joinpath(
            "plots", f"SAMPLES.{wildcards.ref_genome}_{wildcards.ref_graph}_{wildcards.ref_callset}.pg-hwe"
        ),
        sv_min_length = SV_MIN_LENGTH
    shell:
        "MPLBACKEND=Agg python3 {params.script} --cohort-table {input.cohort}"
            " --out-prefix {params.out_prefix} --sv-min-length {params.sv_min_length} &> {log}"


rule plot_pangenie_af_scatter:
    """
    AF scatter plots: allele frequency of each variant in the cohort vs. in the reference
    panel (variants are matched by their ID).
    """
    input:
        cohort = rules.tabulate_pangenie_cohort_variants.output.tsv,
        panel = rules.tabulate_pangenie_panel_variants.output.tsv
    output:
        png = expand(
            DIR_RES.joinpath("plots", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.pg-af-scatter.{variant_class}.png"),
            variant_class=PLOT_VARIANT_CLASSES,
            allow_missing=True
        ),
        pdf = expand(
            DIR_RES.joinpath("plots", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.pg-af-scatter.{variant_class}.pdf"),
            variant_class=PLOT_VARIANT_CLASSES,
            allow_missing=True
        )
    log:
        DIR_LOG.joinpath("50-plotting", "20_plots", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.pg-af-scatter.log")
    benchmark:
        DIR_RSRC.joinpath("50-plotting", "20_plots", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.pg-af-scatter.rsrc")
    conda:
        DIR_ENVS.joinpath("plotting.yaml")
    threads: CPU_LOW
    resources:
        mem_mb=lambda wildcards, attempt: (32 * 1024) * attempt,
        time_hrs=lambda wildcards, attempt: 2 * attempt
    params:
        script = get_script("plot_af_scatter.py"),
        out_prefix = lambda wildcards: DIR_RES.joinpath(
            "plots", f"SAMPLES.{wildcards.ref_genome}_{wildcards.ref_graph}_{wildcards.ref_callset}.pg-af-scatter"
        ),
        sv_min_length = SV_MIN_LENGTH
    shell:
        "MPLBACKEND=Agg python3 {params.script} --cohort-table {input.cohort} --panel-table {input.panel}"
            " --out-prefix {params.out_prefix} --sv-min-length {params.sv_min_length} &> {log}"


rule plot_pangenie_svs_per_sample:
    """
    Histograms of the number of SVs per sample (all SVs, deletions, insertions).
    """
    input:
        table = rules.summarize_pangenie_svs_per_sample.output.tsv
    output:
        png = DIR_RES.joinpath("plots", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.pg-sv-per-sample.png"),
        pdf = DIR_RES.joinpath("plots", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.pg-sv-per-sample.pdf")
    log:
        DIR_LOG.joinpath("50-plotting", "20_plots", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.pg-sv-per-sample.log")
    conda:
        DIR_ENVS.joinpath("plotting.yaml")
    threads: CPU_LOW
    resources:
        mem_mb=lambda wildcards, attempt: 2048 * attempt,
        time_hrs=lambda wildcards, attempt: 1 * attempt
    params:
        script = get_script("plot_sv_per_sample.py"),
        out_prefix = lambda wildcards, output: str(output.png).removesuffix(".png"),
        sv_min_length = SV_MIN_LENGTH
    shell:
        "MPLBACKEND=Agg python3 {params.script} --table {input.table}"
            " --out-prefix {params.out_prefix} --sv-min-length {params.sv_min_length} &> {log}"


rule run_all_pangenie_diagnostic_plots:
    input:
        plots = expand(
            [
                *rules.plot_pangenie_hwe.output.png,
                *rules.plot_pangenie_hwe.output.pdf,
                *rules.plot_pangenie_af_scatter.output.png,
                *rules.plot_pangenie_af_scatter.output.pdf,
                rules.plot_pangenie_svs_per_sample.output.png,
                rules.plot_pangenie_svs_per_sample.output.pdf
            ],
            ref_genome=REFERENCE_WILDCARD_LOOKUP[ReferenceTypes.GENOME],
            ref_graph=REFERENCE_WILDCARD_LOOKUP[ReferenceTypes.PANGENOME],
            ref_callset=REFERENCE_WILDCARD_LOOKUP[ReferenceTypes.CALLSET]
        )
