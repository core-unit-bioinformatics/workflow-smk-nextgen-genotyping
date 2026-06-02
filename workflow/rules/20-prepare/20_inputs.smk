
rule prepare_sample_input_reads:
    """PanGenie can only process uncompressed read files.
    """
    input:
        reads = lambda wildcards: SAMPLE_INPUT_FILES[wildcards.sample]
    output:
        reads = temp(DIR_PROC.joinpath("20-prepare", "input_reads", "{sample}_reads.fasta"))
    conda:
        DIR_ENVS.joinpath("file_prep.yaml")
    threads: 2
    resources:
        mem_mb=lambda wildcards, attempt: 2048 * attempt,
        time_hrs=lambda wildcards, attempt: attempt * attempt
    params:
        cmd=lambda wildcards, input, output: select_prepare_sample_input_reads_command(
            wildcards.sample, input.reads, output.reads
        )
    shell:
        "{params.cmd}"
