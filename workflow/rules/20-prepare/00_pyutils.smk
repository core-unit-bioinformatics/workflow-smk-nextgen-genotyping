
def select_prepare_sample_input_reads_command(sample, input_read_files, output_read_file, nthreads):
    """"""

    if SAMPLE_COMPRESSED_INPUT[sample]:
        cmd = f"pigz -p {nthreads} -d -c {input_read_files} | seqtk seq -A > {output_read_file}"
    else:
        cmd = f"cat {input_read_files} | seqtk seq -A > {output_read_file}"
    return cmd


def select_prepare_gzipped_reference_command(input_reference, output_reference, nthreads):
    """"""

    if isinstance(input_reference, str):
        pass
    else:
        assert len(input_reference) == 1, input_reference
        input_reference = input_reference[0]

    input_reference = pathlib.Path(input_reference)

    if input_reference.suffix == ".gz":
        cmd = f"pigz -p {nthreads} -d -c {input_reference} > {output_reference}"
    else:
        cmd = f"ln {input_reference} {output_reference}"
    return cmd


def is_fastq_file(file_path):
    """Return True if file_path looks like a (gzipped) FASTQ file."""
    name = str(file_path).lower()
    return name.endswith((".fastq", ".fastq.gz", ".fq", ".fq.gz"))


def classify_locityper_library_type(sample, sample_files):
    """Infer whether a sample's input reads are usable by locityper,
    and if so whether they are single-end ("se") or paired-end ("pe").

    Locityper requires FASTQ input, and exactly 1 (single-end) or
    2 (paired-end) files per sample. Returns None 
    if the sample is not compatible with locityper and skip it.
    """
    if not all(is_fastq_file(f) for f in sample_files):
        logerr(
            f"WARNING: sample '{sample}' has non-FASTQ input "
            f"({sample_files}) - skipping for locityper genotyping."
        )
        return None

    if len(sample_files) == 1:
        return "se"
    if len(sample_files) == 2:
        return "pe"

    logerr(
        f"WARNING: sample '{sample}' resolves to {len(sample_files)} input "
        "files - locityper requires exactly 1 (single-end) or 2 "
        "(paired-end) FASTQ files; skipping for locityper genotyping."
    )
    return None