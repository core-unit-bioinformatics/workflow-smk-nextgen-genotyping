
rule prepare_linear_reference_genome:
    input:
        ref_genome = lambda wildcards: REFERENCE_FILE_LOOKUP[ReferenceTypes.GENOME][wildcards.ref_genome]
    output:
        genome_fasta = DIR_LOCAL_REF.joinpath("{ref_genome}.fasta")
    conda:
        DIR_ENVS.joinpath("file_prep.yaml")
    threads: CPU_LOW
    resources:
        mem_mb=lambda wildcards, attempt: 1024 * attempt,
        time_hrs=lambda wildcards, attempt: attempt * attempt
    params:
        cmd = lambda wildcards, input, output: select_prepare_gzipped_reference_command(input.ref_genome, output.genome_fasta)
    shell:
        "{params.cmd}"


rule prepare_pangenome_reference_graph:
    input:
        ref_graph = lambda wildcards: REFERENCE_FILE_LOOKUP[ReferenceTypes.PANGENOME][wildcards.ref_graph]
    output:
        graph_vcf = DIR_LOCAL_REF.joinpath("{ref_graph}.vcf")
    conda:
        DIR_ENVS.joinpath("file_prep.yaml")
    threads: CPU_LOW
    resources:
        mem_mb=lambda wildcards, attempt: 1024 * attempt,
        time_hrs=lambda wildcards, attempt: attempt * attempt
    params:
        cmd = lambda wildcards, input, output: select_prepare_gzipped_reference_command(input.ref_graph, output.graph_vcf)
    shell:
        "{params.cmd}"
