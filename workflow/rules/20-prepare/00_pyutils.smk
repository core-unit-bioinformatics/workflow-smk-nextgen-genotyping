
def select_prepare_sample_input_reads_command(sample, input_read_files, output_read_file):

    if SAMPLE_COMPRESSED_INPUT[sample]:
        cmd = f"pgzip -p {{threads}} -d -c {input_read_files} | seqtk seq -A > {output_read_file}"
    else:
        cmd = f"cat {input_read_files} | seqtk seq -A > {output_read_file}"
    return cmd
