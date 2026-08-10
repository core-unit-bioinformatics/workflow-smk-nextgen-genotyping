# Template for developing Snakemake workflows

Brief description of workflow

## Required software environment

Standardized workflows are designed with minimal assumptions about the local software environment.

In essence, the following should suffice to get started:
1. Linux OS: Debian, Ubuntu, CentOS, Rocky and related distributions should be fine
2. Python3: modern is likely better; the current target version can be found in `workflow/env/exec_env.yaml`. Older versions may or may not work.
3. Conda: for automatic setup of all software dependencies
    - Note that you can run the workflow w/o Conda, but then all tools listed under `workflow/envs/*.yaml` [not `dev_env.yaml`] need to be in your `$PATH`.

For a detailed setup guide, please refer to [the workflow documentation](docs/README.md).

**Internal (template) remark**: adapt the above if the workflow deployment has additional requirements (e.g., Apptainer).

## Required input data
Programm call and parameters for execution:
```
snakemake -d ../wd/ --configfile config/parameter_setting1_mhpc.yaml --config samples=/path/to/samples/samplesheet.tsv tools=locityper,pangenie cwd=/path/to/workflow-smk-nextgen-genotyping --profile ../wd/prf_mhpc
```

path | meaning
:--- | :---
../wd/ | working directory (as created with the workflows init.py script)
config/parameter_setting1_mhpc.yaml | config file containing pathsways for different references (examples specified in said file)
/path/to/samples/samplesheet.tsv  | sample sheet containing the columns "sample" , "input_path" (comma separated if >1), and "tech" (sr, hifi or ont)
locityper,pangenie | modules that should be used to process the data
/path/to/workflow-smk-nextgen-genotyping | path to the workflow directory
../wd/prf_mhpc | path to the snakemake profile (as created by snakamake-utils set_profile.py script)

\
Add info here - be concise, and provide more details in [the workflow documentation](docs/README.md).

## Produced output data

Next to different intermediate files
path | meaning
:--- | :---
../wd/results/genotypes/by-sample/pangenie | per-sample data of the pangenie output of all processed samples
../wd/results/genotypes/merged/pangenie | merged data of the pangenie output of all processed samples
../wd/results/genotypes/merged/locityper | merged data of the locityper output of all processed samples

\
Add info here - be concise, and provide more details in [the workflow documentation](docs/README.md).

# Citation

If not indicated otherwise above, please follow [these instructions](CITATION.md) to cite this repository in your own work.
