
import re


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

# matches "_R1_"/"_R1." or "_R2_"/"_R2." (case-insensitive), e.g.
_READ_MATE_PATTERN = re.compile(r"_R([12])([_.])", re.IGNORECASE)


def get_read_mate(file_path):
    """Return 'R1' or 'R2' if file_path follows the standard Illumina
    mate-naming convention (_R1_/_R1./_R2_/_R2.), else None."""
    match = _READ_MATE_PATTERN.search(str(file_path))
    if match is None:
        return None
    return "R1" if match.group(1) == "1" else "R2"


def get_read_mate_key(file_path):
    """Return file_path with the R1/R2 token replaced by a common
    placeholder, so that matching mates (same lane/run, different
    read direction) produce the same key - used to pair up R1/R2
    files correctly when a sample has more than one file pair."""
    return _READ_MATE_PATTERN.sub(r"_R#\2", str(file_path))


def classify_paired_multi_files(sample_files):
    """Try to split sample_files into two equal-sized, correctly
    paired R1/R2 groups based on filename convention. Returns
    (r1_files, r2_files), sorted so index i in each list are true
    mates of each other, or None if the files don't cleanly split
    this way (unrecognized naming, uneven counts, or mismatched
    mate keys between the two groups)."""
    mates = {"R1": [], "R2": []}
    for f in sample_files:
        mate = get_read_mate(f)
        if mate is None:
            return None
        mates[mate].append(f)

    r1_files, r2_files = mates["R1"], mates["R2"]
    if not r1_files or len(r1_files) != len(r2_files):
        return None

    r1_files = sorted(r1_files, key=get_read_mate_key)
    r2_files = sorted(r2_files, key=get_read_mate_key)

    if [get_read_mate_key(f) for f in r1_files] != [get_read_mate_key(f) for f in r2_files]:
        return None

    return r1_files, r2_files


def classify_sample_input_type(sample, sample_files):
    """Classify a sample's input files for use across tools.
    Returns one of:
        "se"       - single-end FASTQ (1 file)
        "pe"       - true paired-end FASTQ mates (exactly 2 files)
        "se-multi" - 2 or more FASTQ files belonging to single-end 
                     technology (hifi, ont); pooled via streaming
        "pe-multi" - 4+ (even count) FASTQ files that cleanly split
                     into matching R1/R2 pairs by filename convention;
                     each mate group concatenated separately, order-
                     matched, so R1/R2 pairing is preserved
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

    # check for paired-end input split across multiple file pairs
    if len(sample_files) % 2 == 0 and classify_paired_multi_files(sample_files) is not None:
        return "pe-multi"

    write_log_message(
        sys.stderr, "WARNING",
        f"sample '{sample}' resolves to {len(sample_files)} input files "
        f"with tech='{tech}' - more than 2 files is only supported for "
        f"{sorted(SINGLE_END_COMPATIBLE_TECH)} technologies, or for "
        "paired-end files that cleanly split into matching R1/R2 pairs "
        "by filename; skipped"
    )
    return None


def build_locityper_reads_argument(sample, reads_input):
    """Build the '-i'/'-a' argument for locityper"""
    sample_type = classify_sample_input_type(sample, SAMPLE_INPUT_FILES[sample])

    if sample_type == "cram":
        result = f"-a {reads_input[0]}"
    else:
        files = " ".join(str(f) for f in reads_input)
        result = f"-i {files}"

    return result