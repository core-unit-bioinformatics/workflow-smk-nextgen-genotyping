# Data preparation for the PanGenie diagnostic plots (HWE, AF scatter, SVs per sample).
# Per-variant tables are derived from the merged multi-sample genotype VCF (cohort)
# and from the reference callset (panel); the per-sample SV counts from the SV subset
# of the merged VCF. The plots themselves are created in 20_diagnostic_plots.smk.

# minimum difference (bp) between the REF and ALT allele length for a variant to count as SV
SV_MIN_LENGTH = 50


rule tabulate_pangenie_cohort_variants:
    """
    Create a compact per-variant table for the genotyped cohort: allele frequency (AF),
    number of called alleles (AN) and samples (NS), number of heterozygous alleles (AC_Het)
    and the variant class (snv, indel, sv, other). The tags are (re-)computed from the
    genotypes of the merged VCF with 'bcftools +fill-tags'.
    """
    input:
        vcf = rules.merge_pangenie_genotypes_to_multisample.output.vcf,
        tbi = rules.merge_pangenie_genotypes_to_multisample.output.tbi
    output:
        tsv = DIR_PROC.joinpath(
            "50-plotting", "10_pangenie", "pl_tab", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.cohort-variants.tsv.gz"
        )
    log:
        DIR_LOG.joinpath(
            "50-plotting", "10_pangenie", "pl_tab", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.cohort-variants.log"
        )
    benchmark:
        DIR_RSRC.joinpath(
            "50-plotting", "10_pangenie", "pl_tab", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.cohort-variants.rsrc"
        )
    conda:
        DIR_ENVS.joinpath("plotting.yaml")
    threads: CPU_LOW
    resources:
        mem_mb=lambda wildcards, attempt: (4 * 1024) * attempt,
        time_hrs=lambda wildcards, attempt: 12 * attempt
    params:
        script = get_script("variant_table.py"),
        sv_min_length = SV_MIN_LENGTH
    shell:
        "( bcftools +fill-tags {input.vcf} --threads {threads} -Ou -- -t AF,AN,NS,AC_Het"
            " | bcftools query -f '%ID\\t%REF\\t%ALT\\t%INFO/AF\\t%INFO/AN\\t%INFO/NS\\t%INFO/AC_Het\\n'"
            " | python3 {params.script} --sv-min-length {params.sv_min_length} -o {output.tsv}"
        " ) &> {log}"


rule tabulate_pangenie_panel_variants:
    """
    Create the same per-variant table for the reference panel (the 'reference_callset').
    The allele frequencies are re-computed from the panel genotypes because the AF/AC/AN
    values stored in the panel VCF do not necessarily match its genotypes.
    The variant IDs are taken from INFO/ID, which is what the cohort VCF uses as its ID.
    """
    input:
        callset = lambda wildcards: REFERENCE_FILE_LOOKUP[ReferenceTypes.CALLSET][wildcards.ref_callset]
    output:
        tsv = DIR_PROC.joinpath(
            "50-plotting", "10_pangenie", "pl_tab", "{ref_callset}.panel-variants.tsv.gz"
        )
    log:
        DIR_LOG.joinpath("50-plotting", "10_pangenie", "pl_tab", "{ref_callset}.panel-variants.log")
    benchmark:
        DIR_RSRC.joinpath("50-plotting", "10_pangenie", "pl_tab", "{ref_callset}.panel-variants.rsrc")
    conda:
        DIR_ENVS.joinpath("plotting.yaml")
    threads: CPU_LOW
    resources:
        mem_mb=lambda wildcards, attempt: (4 * 1024) * attempt,
        time_hrs=lambda wildcards, attempt: 12 * attempt
    params:
        script = get_script("variant_table.py"),
        sv_min_length = SV_MIN_LENGTH
    shell:
        "( bcftools +fill-tags {input.callset} --threads {threads} -Ou -- -t AF,AN,NS,AC_Het"
            " | bcftools query -f '%INFO/ID\\t%REF\\t%ALT\\t%INFO/AF\\t%INFO/AN\\t%INFO/NS\\t%INFO/AC_Het\\n'"
            " | python3 {params.script} --sv-min-length {params.sv_min_length} -o {output.tsv}"
        " ) &> {log}"


rule extract_pangenie_svs:
    """
    Subset the merged multi-sample VCF to SVs, i.e. variants whose REF and ALT allele
    differ in length by at least SV_MIN_LENGTH bp (deletions and insertions).
    """
    input:
        vcf = rules.merge_pangenie_genotypes_to_multisample.output.vcf,
        tbi = rules.merge_pangenie_genotypes_to_multisample.output.tbi
    output:
        vcf = temp(
            DIR_PROC.joinpath("50-plotting", "10_pangenie", "pl_sv", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.svs.vcf.gz")
        )
    log:
        DIR_LOG.joinpath("50-plotting", "10_pangenie", "pl_sv", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.svs.log")
    benchmark:
        DIR_RSRC.joinpath("50-plotting", "10_pangenie", "pl_sv", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.svs.rsrc")
    conda:
        DIR_ENVS.joinpath("plotting.yaml")
    threads: CPU_LOW
    resources:
        mem_mb=lambda wildcards, attempt: (4 * 1024) * attempt,
        time_hrs=lambda wildcards, attempt: 12 * attempt
    params:
        ilen_filter = f"ILEN<=-{SV_MIN_LENGTH} || ILEN>={SV_MIN_LENGTH}"
    shell:
        "bcftools view -i '{params.ilen_filter}' --threads {threads} -Oz -o {output.vcf} {input.vcf} &> {log}"


rule compute_pangenie_sv_stats:
    """
    Run 'bcftools +smpl-stats' on the SV subset: once for all SVs, once for deletions
    only and once for insertions only (per-sample genotype counts). The plugin counts
    genotypes independent of how bcftools classifies the variant type, unlike 'bcftools stats'
    which misses SVs without a shared anchor base.
    """
    input:
        vcf = rules.extract_pangenie_svs.output.vcf
    output:
        stats_all = DIR_PROC.joinpath(
            "50-plotting", "10_pangenie", "pl_sv", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.svs-all.smpl-stats"
        ),
        stats_del = DIR_PROC.joinpath(
            "50-plotting", "10_pangenie", "pl_sv", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.svs-del.smpl-stats"
        ),
        stats_ins = DIR_PROC.joinpath(
            "50-plotting", "10_pangenie", "pl_sv", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.svs-ins.smpl-stats"
        )
    log:
        DIR_LOG.joinpath("50-plotting", "10_pangenie", "pl_sv", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.svs-stats.log")
    benchmark:
        DIR_RSRC.joinpath("50-plotting", "10_pangenie", "pl_sv", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.svs-stats.rsrc")
    conda:
        DIR_ENVS.joinpath("plotting.yaml")
    threads: CPU_LOW
    resources:
        mem_mb=lambda wildcards, attempt: (4 * 1024) * attempt,
        time_hrs=lambda wildcards, attempt: 2 * attempt
    params:
        del_filter = f"ILEN<=-{SV_MIN_LENGTH}",
        ins_filter = f"ILEN>={SV_MIN_LENGTH}"
    shell:
        "( bcftools +smpl-stats {input.vcf} > {output.stats_all}"
            " && "
        "bcftools view -i '{params.del_filter}' {input.vcf} -Ou | bcftools +smpl-stats - > {output.stats_del}"
            " && "
        "bcftools view -i '{params.ins_filter}' {input.vcf} -Ou | bcftools +smpl-stats - > {output.stats_ins}"
        " ) &> {log}"


rule summarize_pangenie_svs_per_sample:
    """
    Count for each sample the SVs with a 0/1 or 1/1 genotype (all SVs, deletions,
    insertions) and write them into a table next to the plots.
    """
    input:
        stats_all = rules.compute_pangenie_sv_stats.output.stats_all,
        stats_del = rules.compute_pangenie_sv_stats.output.stats_del,
        stats_ins = rules.compute_pangenie_sv_stats.output.stats_ins
    output:
        tsv = DIR_RES.joinpath("plots", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.pg-sv-per-sample.tsv")
    log:
        DIR_LOG.joinpath("50-plotting", "10_pangenie", "pl_sv", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.svs-table.log")
    conda:
        DIR_ENVS.joinpath("plotting.yaml")
    threads: CPU_LOW
    resources:
        mem_mb=lambda wildcards, attempt: 2048 * attempt,
        time_hrs=lambda wildcards, attempt: 1 * attempt
    params:
        script = get_script("sv_per_sample_table.py")
    shell:
        "python3 {params.script} --stats-all {input.stats_all} --stats-del {input.stats_del}"
            " --stats-ins {input.stats_ins} -o {output.tsv} &> {log}"
