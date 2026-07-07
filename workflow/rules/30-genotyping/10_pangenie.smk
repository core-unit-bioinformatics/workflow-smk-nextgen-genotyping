SAMPLES_PANGENIE = [
    sample for sample in SAMPLES
    if not any(is_cram_file(f) for f in SAMPLE_INPUT_FILES[sample])
]

for sample in sorted(set(SAMPLES) - set(SAMPLES_PANGENIE)):
    logout(
        f"WARNING: sample '{sample}' provides CRAM input, which pangenie "
        "does not support (requires FASTA/FASTQ reads). Skipped for pangenie."
    )

if not SAMPLES_PANGENIE:
    err_msg = "Error: no samples are compatible with pangenie genotyping (all provide CRAM-only input)."
    logerr(err_msg)
    raise ValueError(err_msg)


rule run_pangenie_indexing:
    input:
        genome = rules.prepare_linear_reference_genome.output.genome_fasta,
        graph = rules.prepare_pangenome_reference_graph.output.graph_vcf
    output:
        idx_dir = directory(
            DIR_PROC.joinpath(
                "30-genotyping", "10_pangenie", "pg_idx", "{ref_genome}_{ref_graph}.idx"
            )
        )
    log:
        DIR_LOG.joinpath("30-genotyping", "10_pangenie", "pg_idx", "{ref_genome}_{ref_graph}.idx.log")
    benchmark:
        DIR_RSRC.joinpath("30-genotyping", "10_pangenie", "pg_idx", "{ref_genome}_{ref_graph}.idx.rsrc")
    conda:
        DIR_ENVS.joinpath("pangenie.yaml")
    threads: CPU_MEDIUM
    resources:
        mem_mb=lambda wildcards, attempt: 65536 + 65536 * attempt,
        time_hrs=lambda wildcards, attempt: 4 * attempt
    params:
       idx_prefix = lambda wildcards, output: pathlib.Path(output.idx_dir).joinpath(f"{wildcards.ref_genome}_{wildcards.ref_graph}")
    shell:
        "mkdir -p {output.idx_dir}"
            " && "
        "PanGenie-index -v {input.graph} -r {input.genome} -o {params.idx_prefix} -t {threads} &> {log}"


rule run_pangenie_genotyping:
    input:
        reads =  rules.prepare_sample_input_reads.output.reads,
        idx_dir = rules.run_pangenie_indexing.output.idx_dir
    output:
        vcf = temp(
            DIR_PROC.joinpath("30-genotyping", "10_pangenie", "pg_gt", "{sample}.{ref_genome}_{ref_graph}_genotyping.vcf")
        )
    log:
        DIR_LOG.joinpath("30-genotyping", "10_pangenie", "pg_gt", "{sample}.{ref_genome}_{ref_graph}.pg-run.log")
    benchmark:
        DIR_RSRC.joinpath("30-genotyping", "10_pangenie", "pg_gt", "{sample}.{ref_genome}_{ref_graph}.pg-run.rsrc")
    conda:
        DIR_ENVS.joinpath("pangenie.yaml")
    threads: CPU_HIGH
    resources:
        mem_mb=lambda wildcards, attempt: (64 * 1024) + (8192 * attempt-1),
        time_hrs=lambda wildcards, attempt: 12 * attempt
    params:
        out_prefix = lambda wildcards, output: str(output.vcf).rsplit("_",1)[0],
        idx_prefix = lambda wildcards, input: pathlib.Path(input.idx_dir).joinpath(f"{wildcards.ref_genome}_{wildcards.ref_graph}")
    shell:
        "PanGenie -f {params.idx_prefix} -i {input.reads} -o {params.out_prefix} -t {threads} -j {threads} -s {wildcards.sample} &> {log}"


rule convert_pangenie_genotypes_to_biallelic:
    input:
        vcf = rules.run_pangenie_genotyping.output.vcf,
        ref_callset = lambda wildcards: REFERENCE_FILE_LOOKUP[ReferenceTypes.CALLSET][wildcards.ref_callset]
    output:
        vcf = DIR_RES.joinpath("genotypes", "by-sample", "pangenie", "{sample}.{ref_genome}_{ref_graph}_{ref_callset}.pg-gt-bi.vcf.gz"),
        tbi = DIR_RES.joinpath("genotypes", "by-sample", "pangenie", "{sample}.{ref_genome}_{ref_graph}_{ref_callset}.pg-gt-bi.vcf.gz.tbi")
    benchmark:
        DIR_RSRC.joinpath("30-genotyping", "10_pangenie", "pg_conv", "{sample}.{ref_genome}_{ref_graph}_{ref_callset}.pg-conv.rsrc")
    conda:
        DIR_ENVS.joinpath("pangenie.yaml")
    resources:
        mem_mb=lambda wildcards, attempt: 24576 * attempt,
        time_hrs=lambda wildcards, attempt: attempt * attempt   # intentionally exponential?
    params:
        script=get_script("convert-to-biallelic.py")
    shell:
        "cat {input.vcf} | {params.script} {input.ref_callset} | bgzip > {output.vcf}"
            " && "
        "tabix -p vcf {output.vcf}"


rule merge_pangenie_genotypes_to_multisample:
    input:
        vcf = expand(
            rules.convert_pangenie_genotypes_to_biallelic.output.vcf,
            sample=SAMPLES_PANGENIE,
            allow_missing=True
        ),
        tbi = expand(
            rules.convert_pangenie_genotypes_to_biallelic.output.tbi,
            sample=SAMPLES_PANGENIE,
            allow_missing=True
        )
    output:
        vcf = DIR_RES.joinpath("genotypes", "merged", "pangenie", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.pg-gt-bi.vcf.gz"),
        tbi = DIR_RES.joinpath("genotypes", "merged", "pangenie", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.pg-gt-bi.vcf.gz.tbi"),
    benchmark:
        DIR_RSRC.joinpath("30-genotyping", "10_pangenie", "pg_merge", "SAMPLES.{ref_genome}_{ref_graph}_{ref_callset}.pg-merge.rsrc")
    conda:
        DIR_ENVS.joinpath("pangenie.yaml")
    resources:
        mem_mb=lambda wildcards, attempt: 4096 * attempt,
        time_hrs=lambda wildcards, attempt: attempt * attempt
    params:
        force_single = lambda wildcards, input: "--force-single" if len(input.vcf) == 1 else ""
    shell:
        "bcftools merge {params.force_single} {input.vcf} -Oz -o {output.vcf}"
            " && "
        "tabix -p vcf {output.vcf}"


rule run_all_pangenie_genotyping:
    input:
        vcf = expand(
            rules.merge_pangenie_genotypes_to_multisample.output.vcf,
            ref_genome=REFERENCE_WILDCARD_LOOKUP[ReferenceTypes.GENOME],
            ref_graph=REFERENCE_WILDCARD_LOOKUP[ReferenceTypes.PANGENOME],
            ref_callset=REFERENCE_WILDCARD_LOOKUP[ReferenceTypes.CALLSET]
        )
