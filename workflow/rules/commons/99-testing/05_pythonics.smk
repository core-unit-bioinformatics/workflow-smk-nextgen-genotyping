"""Testing module for Python
helper functions (logging, get_script etc)
"""


rule create_test_file:
    """
    Implicitly tests pyutil functions
    02_pyutils.smk::get_username
    02_pyutils.smk::get_timestamp
    """
    output:
        DIR_PROC.joinpath("testing", "ts-ok_user-ok.txt"),
    params:
        acc_in=lambda wildcards, output: register_input(output, allow_non_existing=True),
    run:
        timestamp = get_timestamp()
        user_id = get_username()
        host = get_hostname()
        content = "Running Snakemake tests\n"
        content += f"get_username: {user_id}\n"
        content += f"get_timestamp: {timestamp}\n"
        content += f"get_hostname: {host}\n"
        with open(output[0], "w") as testfile:
            _ = testfile.write(content)
            _ = testfile.write("Creating test input file succeeded")
        # END OF RUN BLOCK


rule test_log_functions:
    """
    Test pyutil logging functions
    """
    output:
        DIR_PROC.joinpath("testing", "log-{logtype}-ok.txt"),
    params:
        acc_out=lambda wildcards, output: register_result(output),
    run:
        if wildcards.logtype == "out":
            logout("Test log message to STDOUT")
        elif wildcards.logtype == "err":
            logerr("Test log message to STDERR")
        else:
            raise ValueError(f"Unknown log type: {wildcards.logtype}")
        with open(output[0], "w") as testfile:
            testfile.write(f"Log test {wildcards.logtype} ok")
        # END OF RUN BLOCK


rule test_find_script_success:
    input:
        rules.create_test_file.output,
    output:
        DIR_PROC.joinpath("testing", "success-get-script-ok.txt"),
    params:
        script=get_script("test"),
        acc_out=lambda wildcards, output: register_result(output),
    run:
        import pathlib  # workaround, see gh#20

        # the following should never raise,
        # i.e. script_find() would fail before
        _ = pathlib.Path(params.script).resolve(strict=True)
        with open(output[0], "w") as testfile:
            testfile.write("find_script success test ok")
        # END OF RUN BLOCK


rule test_find_script_fail:
    input:
        rules.test_find_script_success.output,
    output:
        DIR_PROC.joinpath("testing", "fail-get-script-ok.txt"),
    params:
        acc_out=lambda wildcards, output: register_result(output),
    run:
        try:
            script = get_script("non_existing")
            # the previous line should not succeed,
            # if we are here, we do not create the
            # output file of the test, and thus fail
        except ValueError:
            with open(output[0], "w") as testfile:
                testfile.write("find_script fail test ok")
        # END OF RUN BLOCK


rule test_git_labels:
    input:
        rules.create_test_file.output,
    output:
        out=DIR_PROC.joinpath("testing", "git-labels-ok.txt"),
    params:
        acc_out=lambda wildcards, output: register_result(output.out),
    run:
        git_labels = collect_git_labels()
        with open(output[0], "w") as labels:
            for label, value in git_labels:
                _ = labels.write(f"{label}\t{value}\n")
        # END OF RUN BLOCK


rule create_sample_sheet:
    output:
        tsv=DIR_PROC.joinpath("testing", "sample_sheet.{variant}.tsv"),
    params:
        acc_out=lambda wildcards, output: register_result(output.tsv),
    run:
        import io

        buffer = io.StringIO()
        buffer.write("# comment line\n#more comments\n")
        if wildcards.variant == "invalid":
            buffer.write("sample-id\tinput.data\tother\n")
        elif wildcards.variant == "incomplete":
            buffer.write("sample_id\tmetadata\n")
        else:
            buffer.write("sample_id\tinput_data\tmetadata\n")
        if wildcards.variant == "incomplete":
            buffer.write("sample.a\tfoo\n")
            buffer.write("sample-b\tbar\n")
        else:
            buffer.write("sample.a\t/path/to/a\tfoo\n")
            buffer.write("sample-b\t/path/to/data/b\tbar\n")
        with open(output.tsv, "w", encoding="ascii") as table:
            table.write(buffer.getvalue())
        # END OF RUN BLOCK


rule test_read_samplesheet:
    input:
        tsv=rules.create_sample_sheet.output.tsv,
    output:
        ok=DIR_PROC.joinpath("testing", "sample_sheet.{variant}.read.ok"),
    params:
        acc_out=lambda wildcards, output: register_result(output.ok),
    run:
        if wildcards.variant == "invalid":
            try:
                _ = read_sample_sheet(input.tsv, MSSC)
            except ValueError:
                with open(output.ok, "w") as testfile:
                    _ = testfile.write("sample sheet invalid header test ok")
        elif wildcards.variant == "incomplete":
            try:
                _ = read_sample_sheet(input.tsv, MSSC)
            except RuntimeError:
                with open(output.ok, "w") as testfile:
                    _ = testfile.write("sample sheet incomplete header test ok")
        else:
            sample_sheet = read_sample_sheet(input.tsv, MSSC)
            samples = sorted(set(sample_sheet[MSSC.sample]))
            assert "sample.a" in samples
            assert "sample-b" in samples
            with open(output.ok, "w") as testfile:
                _ = testfile.write("sample sheet read test ok")
        # END OF RUN BLOCK


rule test_all_pythonics:
    input:
        rules.create_test_file.output,
        expand(rules.test_log_functions.output, logtype=["err", "out"]),
        rules.test_find_script_success.output,
        rules.test_find_script_success.output,
        rules.test_git_labels.output,
        expand(
            rules.test_read_samplesheet.output,
            variant=["invalid", "incomplete", "valid"],
        ),
