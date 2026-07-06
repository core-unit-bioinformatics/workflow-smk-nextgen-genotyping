import pathlib

# Not every sample in the sample sheet is necessarily usable by
# locityper (it requires FASTQ input and 1 or 2 files per sample).
# Incompatible samples are skipped here (with a warning) but remain
# unaffected for other tools such as pangenie.

SAMPLES_LOCITYPER = [
    sample for sample in SAMPLES
    if classify_sample_input_type(sample, SAMPLE_INPUT_FILES[sample]) is not None
]


if not SAMPLES_LOCITYPER:
    err_msg = (
        "Error: no samples are compatible with locityper genotyping "
        "(need 1 or 2 FASTQ read files per sample)."
    )
    logerr(err_msg)
    raise ValueError(err_msg)


CRAM_SAMPLES_PRESENT = any(
    classify_sample_input_type(sample, SAMPLE_INPUT_FILES[sample]) == "cram"
    for sample in SAMPLES_LOCITYPER
)

if CRAM_SAMPLES_PRESENT:
    if "cram_reference_genome" not in config:
        err_msg = (
            "Error: at least one sample provides CRAM input, but no "
            "'cram_reference_genome' is configured. CRAM decoding requires "
            "the exact reference used to produce the CRAM (see its header), "
            "Please add a'cram_reference_genome: {label, path}' to the config."
        )
        logerr(err_msg)
        raise ValueError(err_msg)

    CRAM_REFERENCE_GENOME_PATH = pathlib.Path(config["cram_reference_genome"]["path"])
    if not CRAM_REFERENCE_GENOME_PATH.is_file():
        err_msg = f"Configured cram_reference_genome file is not accessible: {CRAM_REFERENCE_GENOME_PATH}"
        logerr(err_msg)
        raise FileNotFoundError(err_msg)


# reference/index preparation 

rule index_locityper_reference_genome:
    """samtools faidx the reference genome(locityper
    expects the .fai index to sit alongside the FASTA)."""
    input:
        genome_fasta = rules.prepare_linear_reference_genome.output.genome_fasta
    output:
        genome_index = DIR_LOCAL_REF.joinpath("{ref_genome}.fasta.fai")
    log:
        DIR_LOG.joinpath("30-genotyping", "20_locityper", "lt_ref", "{ref_genome}.faidx.log")
    benchmark:
        DIR_RSRC.joinpath("30-genotyping", "20_locityper", "lt_ref", "{ref_genome}.faidx.rsrc")
    conda:
        DIR_ENVS.joinpath("locityper.yaml")
    threads: CPU_LOW
    resources:
        mem_mb=lambda wildcards, attempt: 4096 * attempt,
        time_hrs=lambda wildcards, attempt: 2 * attempt
    shell:
        "samtools faidx {input.genome_fasta} &> {log}"


if CRAM_SAMPLES_PRESENT:

    rule prepare_locityper_cram_reference_genome:
            """Stage/decompress the CRAM-specific reference genome. This must
            exactly match what's specified in the CRAM header - see the CRAM
            format spec - and may differ from 'linear_reference_genome'."""
            input:
                raw_reference = CRAM_REFERENCE_GENOME_PATH
            output:
                genome_fasta = DIR_LOCAL_REF.joinpath("cram_reference.fasta")
            log:
                DIR_LOG.joinpath("30-genotyping", "20_locityper", "lt_cram", "cram_reference.prep.log")
            benchmark:
                DIR_RSRC.joinpath("30-genotyping", "20_locityper", "lt_cram", "cram_reference.prep.rsrc")
            conda:
                DIR_ENVS.joinpath("file_prep.yaml")
            threads: CPU_LOW
            resources:
                mem_mb=lambda wildcards, attempt: 2048 * attempt,
                time_hrs=lambda wildcards, attempt: attempt
            params:
                cmd = lambda wildcards, threads, input, output: select_prepare_gzipped_reference_command(
                    input.raw_reference, output.genome_fasta, threads
                )
            shell:
                "{params.cmd} &> {log}"


    rule index_locityper_cram_reference_genome:
        input:
            genome_fasta = rules.prepare_locityper_cram_reference_genome.output.genome_fasta
        output:
            genome_index = DIR_LOCAL_REF.joinpath("cram_reference.fasta.fai")
        log:
            DIR_LOG.joinpath("30-genotyping", "20_locityper", "lt_cram", "cram_reference.faidx.log")
        benchmark:
            DIR_RSRC.joinpath("30-genotyping", "20_locityper", "lt_cram", "cram_reference.faidx.rsrc")
        conda:
            DIR_ENVS.joinpath("locityper.yaml")
        threads: CPU_LOW
        resources:
            mem_mb=lambda wildcards, attempt: 1024 * attempt,
            time_hrs=lambda wildcards, attempt: attempt
        shell:
            "samtools faidx {input.genome_fasta} &> {log}"


rule index_locityper_cram_alignment:
    """samtools index for CRAM input samples - required before locityper
    preproc/genotype can read the alignment."""
    input:
        alignment = lambda wildcards: SAMPLE_INPUT_FILES[wildcards.sample][0]
    output:
        alignment_index = DIR_PROC.joinpath(
            "30-genotyping", "20_locityper", "lt_cram", "{sample}.cram.crai"
        )
    log:
        DIR_LOG.joinpath("30-genotyping", "20_locityper", "lt_cram", "{sample}.cram-index.log")
    benchmark:
        DIR_RSRC.joinpath("30-genotyping", "20_locityper", "lt_cram", "{sample}.cram-index.rsrc")
    conda:
        DIR_ENVS.joinpath("locityper.yaml")
    threads: CPU_LOW
    resources:
        mem_mb=lambda wildcards, attempt: 2048 * attempt,
        time_hrs=lambda wildcards, attempt: attempt
    shell:
        "samtools index -o {output.alignment_index} --threads {threads} {input.alignment} &> {log}"


rule count_locityper_reference_kmers:
    """Count canonical k-mers in the reference genome for locityper."""
    input:
        genome_fasta = rules.prepare_linear_reference_genome.output.genome_fasta,
        genome_index = rules.index_locityper_reference_genome.output.genome_index
    output:
        jf_counts = DIR_PROC.joinpath("30-genotyping", "20_locityper", "lt_ref", "{ref_genome}.counts.jf")
    log:
        DIR_LOG.joinpath("30-genotyping", "20_locityper", "lt_ref", "{ref_genome}.jf-count.log")
    benchmark:
        DIR_RSRC.joinpath("30-genotyping", "20_locityper", "lt_ref", "{ref_genome}.jf-count.rsrc")
    conda:
        DIR_ENVS.joinpath("locityper.yaml")
    threads: CPU_MEDIUM
    resources:
        mem_mb=lambda wildcards, attempt: (32 * 1024) * attempt,
        time_hrs=lambda wildcards, attempt: 4 * attempt
    shell:
        "jellyfish count --canonical --lower-count 2 --out-counter-len 2"
            " --mer-len 25 --threads {threads} --size 3G"
            " --output {output.jf_counts} {input.genome_fasta} &> {log}"


rule filter_pangenome_graph_overlaps:
    """Remove overlapping variants from the shared pangenome graph VCF."""
    input:
        graph_vcf = rules.prepare_pangenome_reference_graph.output.graph_vcf
    output:
        filtered_graph = DIR_PROC.joinpath(
            "30-genotyping", "20_locityper", "lt_ref", "{ref_graph}.no-overlaps.vcf.gz"
        ),
        tbi = DIR_PROC.joinpath(
            "30-genotyping", "20_locityper", "lt_ref", "{ref_graph}.no-overlaps.vcf.gz.tbi"
        )
    log:
        DIR_LOG.joinpath("30-genotyping", "20_locityper", "lt_ref", "{ref_graph}.vcfbub.log")
    benchmark:
        DIR_RSRC.joinpath("30-genotyping", "20_locityper", "lt_ref", "{ref_graph}.vcfbub.rsrc")
    conda:
        DIR_ENVS.joinpath("locityper.yaml")
    resources:
        mem_mb=lambda wildcards, attempt: 4096 * attempt,
        time_hrs=lambda wildcards, attempt: 2 * attempt
    shell:
        "vcfbub -l 0 -i {input.graph_vcf} 2> {log} | bgzip > {output.filtered_graph}"
            " && "
        "tabix -p vcf {output.filtered_graph}"


rule build_locityper_loci_database:
    """Create the locityper loci database ('locityper target')."""
    input:
        genome_fasta = rules.prepare_linear_reference_genome.output.genome_fasta,
        genome_index = rules.index_locityper_reference_genome.output.genome_index,
        filtered_graph = rules.filter_pangenome_graph_overlaps.output.filtered_graph,
        jf_counts = rules.count_locityper_reference_kmers.output.jf_counts,
        loci_coordinates = lambda wildcards: REFERENCE_FILE_LOOKUP[ReferenceTypes.LOCI_CATALOG][wildcards.ref_loci]
    output:
        loci_db = directory(
            DIR_PROC.joinpath(
                "30-genotyping", "20_locityper", "lt_db", "{ref_genome}_{ref_graph}_{ref_loci}.loci_db"
            )
        )
    log:
        DIR_LOG.joinpath("30-genotyping", "20_locityper", "lt_db", "{ref_genome}_{ref_graph}_{ref_loci}.target.log")
    benchmark:
        DIR_RSRC.joinpath("30-genotyping", "20_locityper", "lt_db", "{ref_genome}_{ref_graph}_{ref_loci}.target.rsrc")
    conda:
        DIR_ENVS.joinpath("locityper.yaml")
    threads: CPU_MEDIUM
    resources:
        mem_mb=lambda wildcards, attempt: 16384 * attempt,
        time_hrs=lambda wildcards, attempt: 4 * attempt
    shell:
        "locityper target -d {output.loci_db} -v {input.filtered_graph}"
            " -r {input.genome_fasta} -j {input.jf_counts}"
            " -L {input.loci_coordinates} &> {log}"


# per-sample preprocessing + genotyping 
rule preprocess_locityper_reads:
    """Run 'locityper preproc' (handles single-end FASTQ,
    paired-end FASTQ, and CRAM input)."""
    input:
        reads = lambda wildcards: SAMPLE_INPUT_FILES[wildcards.sample],
        alignment_index = lambda wildcards: (
            expand(rules.index_locityper_cram_alignment.output.alignment_index, sample=[wildcards.sample])
            if classify_sample_input_type(wildcards.sample, SAMPLE_INPUT_FILES[wildcards.sample]) == "cram"
            else []
        ),
        reference_fasta = lambda wildcards: (
            rules.prepare_locityper_cram_reference_genome.output.genome_fasta
            if classify_sample_input_type(wildcards.sample, SAMPLE_INPUT_FILES[wildcards.sample]) == "cram"
            else rules.prepare_linear_reference_genome.output.genome_fasta
        ),
        genome_index = rules.index_locityper_reference_genome.output.genome_index,
        jf_counts = rules.count_locityper_reference_kmers.output.jf_counts
    output:
        preproc_dir = directory(
            DIR_PROC.joinpath("30-genotyping", "20_locityper", "lt_pre", "{sample}.{ref_genome}_reads-test")
        )
    log:
        DIR_LOG.joinpath("30-genotyping", "20_locityper", "lt_pre", "{sample}.{ref_genome}.preproc.log")
    benchmark:
        DIR_RSRC.joinpath("30-genotyping", "20_locityper", "lt_pre", "{sample}.{ref_genome}.preproc.rsrc")
    conda:
        DIR_ENVS.joinpath("locityper.yaml")
    threads: CPU_MEDIUM
    resources:
        mem_mb=lambda wildcards, attempt: 8192 * attempt,
        time_hrs=lambda wildcards, attempt: attempt
    params:
        read_flag = lambda wildcards: (
            "-a" if classify_sample_input_type(wildcards.sample, SAMPLE_INPUT_FILES[wildcards.sample]) == "cram"
            else "-i"
        )
    shell:
        "locityper preproc {params.read_flag} {input.reads} -r {input.reference_fasta}"
            " -j {input.jf_counts} -o {output.preproc_dir}"
            " --threads {threads} &> {log}"


rule locityper_genotype_sample:
    """Run 'locityper genotype' (handles single-end FASTQ,
    paired-end FASTQ, and CRAM input)."""
    input:
        reads = lambda wildcards: SAMPLE_INPUT_FILES[wildcards.sample],
        alignment_index = lambda wildcards: (
            expand(rules.index_locityper_cram_alignment.output.alignment_index, sample=[wildcards.sample])
            if classify_sample_input_type(wildcards.sample, SAMPLE_INPUT_FILES[wildcards.sample]) == "cram"
            else []
        ),
        loci_database = rules.build_locityper_loci_database.output.loci_db,
        preproc_dir = rules.preprocess_locityper_reads.output.preproc_dir
    output:
        genotype_dir = directory(
            DIR_PROC.joinpath("30-genotyping", "20_locityper", "lt_gt", "{sample}.{ref_genome}_{ref_graph}_{ref_loci}")
        )
    log:
        DIR_LOG.joinpath(
            "30-genotyping", "20_locityper", "lt_gt",
            "{sample}.{ref_genome}_{ref_graph}_{ref_loci}.genotype.log"
        )
    benchmark:
        DIR_RSRC.joinpath(
            "30-genotyping", "20_locityper", "lt_gt",
            "{sample}.{ref_genome}_{ref_graph}_{ref_loci}.genotype.rsrc"
        )
    conda:
        DIR_ENVS.joinpath("locityper.yaml")
    threads: CPU_HIGH
    resources:
        mem_mb=lambda wildcards, attempt: 16384 * attempt,
        time_hrs=lambda wildcards, attempt: attempt
    params:
        read_flag = lambda wildcards: (
            "-a" if classify_sample_input_type(wildcards.sample, SAMPLE_INPUT_FILES[wildcards.sample]) == "cram"
            else "-i"
        ),
        ref_flag = lambda wildcards: (
            f"-r {rules.prepare_locityper_cram_reference_genome.output.genome_fasta}"
            if classify_sample_input_type(wildcards.sample, SAMPLE_INPUT_FILES[wildcards.sample]) == "cram"
            else ""
        )
    shell:
        "locityper genotype {params.read_flag} {input.reads} -d {input.loci_database}"
            " -p {input.preproc_dir} {params.ref_flag} -o {output.genotype_dir}"
            " --threads {threads} &> {log}"


# aggregation into a single CSV

rule create_locityper_sample_manifest:
    """Write a (path, sample) manifest for merge by into_csv.py -I."""
    input:
        sample_dirs = expand(
            rules.locityper_genotype_sample.output.genotype_dir,
            sample=SAMPLES_LOCITYPER,
            allow_missing=True
        )
    output:
        manifest = DIR_PROC.joinpath(
            "30-genotyping", "20_locityper", "lt_csv",
            "{ref_genome}_{ref_graph}_{ref_loci}.manifest.tsv"
        )
    run:
        with open(output.manifest, "w") as dump:
            for sample, sample_dir in zip(SAMPLES_LOCITYPER, input.sample_dirs):
                dump.write(f"{sample_dir}\t{sample}\n")


rule merge_locityper_genotypes_to_csv:
    input:
        manifest = rules.create_locityper_sample_manifest.output.manifest
    output:
        csv = DIR_RES.joinpath(
            "genotypes", "merged", "locityper",
            "SAMPLES.{ref_genome}_{ref_graph}_{ref_loci}.lt-gt.csv"
        )
    log:
        DIR_LOG.joinpath(
            "30-genotyping", "20_locityper", "lt_csv",
            "{ref_genome}_{ref_graph}_{ref_loci}.into-csv.log"
        )
    benchmark:
        DIR_RSRC.joinpath(
            "30-genotyping", "20_locityper", "lt_csv",
            "{ref_genome}_{ref_graph}_{ref_loci}.into-csv.rsrc"
        )
    conda:
        DIR_ENVS.joinpath("locityper.yaml")
    threads: CPU_LOW
    resources:
        mem_mb=lambda wildcards, attempt: 2048 * attempt,
        time_hrs=lambda wildcards, attempt: 2 * attempt
    params:
        script = get_script("into_csv.py")
    shell:
        "python3 {params.script} -I {input.manifest} -o {output.csv}"
            " --threads {threads} &> {log}"


rule run_all_locityper_genotyping:
    input:
        csv = expand(
            rules.merge_locityper_genotypes_to_csv.output.csv,
            ref_genome=REFERENCE_WILDCARD_LOOKUP[ReferenceTypes.GENOME],
            ref_graph=REFERENCE_WILDCARD_LOOKUP[ReferenceTypes.PANGENOME],
            ref_loci=REFERENCE_WILDCARD_LOOKUP[ReferenceTypes.LOCI_CATALOG]
        )