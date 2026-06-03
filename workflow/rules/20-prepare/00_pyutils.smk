
def select_prepare_sample_input_reads_command(sample, input_read_files, output_read_file):
    """"""

    if SAMPLE_COMPRESSED_INPUT[sample]:
        cmd = f"pgzip -p {{threads}} -d -c {input_read_files} | seqtk seq -A > {output_read_file}"
    else:
        cmd = f"cat {input_read_files} | seqtk seq -A > {output_read_file}"
    return cmd


def select_prepare_gzipped_reference_command(input_reference, output_reference):
    """"""

    if isinstance(input_reference, str):
        pass
    else:
        assert len(input_reference) == 1, input_reference
        input_reference = input_reference[0]

    input_reference = pathlib.Path(input_reference)

    if input_reference.suffix == ".gz":
        cmd = f"pgzip -p {{threads}} -d -c {input_reference} > {output_reference}"
    else:
        cmd = f"ln {input_reference} {output_reference}"
    return cmd
