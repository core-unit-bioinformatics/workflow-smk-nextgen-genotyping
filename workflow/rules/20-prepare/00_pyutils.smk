
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


def is_cram_file(file_path):
    """Return True if file_path looks like a CRAM alignment file."""
    return str(file_path).lower().endswith(".cram")


def classify_sample_input_type(sample, sample_files):
    """Classify a sample's input files for use across tools.

    Returns one of:
        "se"   - single-end FASTQ (1 file)
        "pe"   - paired-end FASTQ (2 files)
        "cram" - single CRAM alignment file
        None   - incompatible/unrecognized combination; callers should
                 skip this sample for whichever tool required this
                 classification (see e.g. SAMPLES_LOCITYPER)
    """

    if len(sample_files) == 1 and is_cram_file(sample_files[0]):
        return "cram"

    if not all(is_fastq_file(f) for f in sample_files):
        logerr(
            f"WARNING: sample '{sample}' has input that is neither FASTQ "
            f"nor a single CRAM file ({sample_files}). Skipped for locityper."
            
        )
        return None

    if len(sample_files) == 1:
        return "se"
    if len(sample_files) == 2:
        return "pe"

    logerr(
        f"WARNING: sample '{sample}' resolves to {len(sample_files)} input "
        f"files. Expected 1 (single-end FASTQ or CRAM) or 2 "
        f"(paired-end FASTQ) files. Skipped for locityper."
    )
    return None