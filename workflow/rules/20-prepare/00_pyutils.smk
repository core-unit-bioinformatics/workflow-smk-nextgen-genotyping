
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


SINGLE_END_COMPATIBLE_TECH = {"hifi", "ont"}


def classify_sample_input_type(sample, sample_files):
    """Classify a sample's input files for use across tools.
    Returns one of:
        "se"       - single-end FASTQ (1 file)
        "pe"       - true paired-end FASTQ mates (exactly 2 files)
        "se-multi" - 2 or more FASTQ files belonging to single-end 
                     technology (hifi, ont); pooled via streaming
        "cram"     - single CRAM alignment file
        None       - incompatible/unrecognized combination; caller should skip
    """

    # check for cram input
    if len(sample_files) == 1 and is_cram_file(sample_files[0]):
        return "cram"

    if not all(is_fastq_file(f) for f in sample_files):
        write_log_message(
            sys.stderr, "WARNING",
            f"sample '{sample}' has input that is neither FASTQ nor a "
            f"single CRAM file ({sample_files}) - skipping for tools that "
            "require classified read input (e.g. locityper)."
        )
        return None

    # check for single-end input
    if len(sample_files) == 1:
        return "se"

    tech = SAMPLE_TECH.get(sample)

    # check for single-end compatible technologies that may have multiple FASTQ files
    if tech in SINGLE_END_COMPATIBLE_TECH:
        return "se-multi"

    # check for paired-end input
    if len(sample_files) == 2:
        return "pe"

    write_log_message(
        sys.stderr, "WARNING",
        f"sample '{sample}' resolves to {len(sample_files)} input files "
        f"with tech='{tech}' - more than 2 files is only supported for "
        f"{sorted(SINGLE_END_COMPATIBLE_TECH)} technologies; skipped"
    )
    return None


def build_locityper_reads_argument(sample, sample_files):
    """Build the '-i'/'-a' argument (flag + files) for locityper"""

    sample_type = classify_sample_input_type(sample, sample_files)

    if sample_type == "cram":
        return f"-a {sample_files[0]}"

    if sample_type in ("se", "pe"):
        files = " ".join(str(f) for f in sample_files)
        return f"-i {files}"

    if sample_type == "se-multi":
        cat_cmd = "zcat" if SAMPLE_COMPRESSED_INPUT[sample] else "cat"
        files = " ".join(str(f) for f in sample_files)
        return f"-i <({cat_cmd} {files})"

    raise ValueError(
        f"Cannot build locityper reads argument for sample '{sample}' "
        f"(classified as {sample_type!r})"
    )