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
Program call and parameters for execution:
```
snakemake -d ../wd/ --configfile config/parameter_setting1_mhpc.yaml --config samples=/path/to/samples/samplesheet.tsv cwd=/path/to/workflow-smk-nextgen-genotyping tools=locityper,pangenie graph_type=agc max_temp_disk_mb=20000000 max_temp_pangenie_mb=40000 max_temp_locityper_mb=100000 --profile ../wd/prf_mhpc
```

| Parameter | Description |
|---|---|
| `-d ../wd/` | Working directory (as created with the workflows init.py script) |
| `--configfile config/parameter_setting1_mhpc.yaml` | Config file containing paths for different references (examples specified in said file) |
| `--config` | Needed parameter before the following ones (only called once, not in front of every one) |
| &emsp;`/path/to/samples/samplesheet.tsv` | Sample sheet containing the columns "sample", "input_path" (comma separated if >1), and "tech" (sr, hifi or ont) |
| &emsp;`locityper,pangenie` | Modules that should be used to process the data |
| &emsp;`agc OR vcf` | Locityper processing pathway, either agc or vcf |
| &emsp;`max_temp_disk_mb=20000000` | Maximum space allocated for simultaneous temporary files |
| &emsp;`max_temp_pangenie_mb=40000` | Assumed size of temporary files per sample for the pangenie module |
| &emsp;`max_temp_locityper_mb=100000` | Assumed size of temporary files per sample for the locityper module |
| &emsp;`/path/to/workflow-smk-nextgen-genotyping` | Path to the workflow directory |
| `--profile ../wd/prf_mhpc` | Path to the snakemake profile (as created by snakemake-utils set_profile.py script) |

\
Add info here - be concise, and provide more details in [the workflow documentation](docs/README.md).

## Produced output data

Next to different intermediate files the following main output files are generated:

| Path | Description |
|---|---|
| `../wd/results/genotypes/by-sample/pangenie` | Per-sample data of the pangenie output of all processed samples |
| `../wd/results/genotypes/merged/pangenie` | Merged data of the pangenie output of all processed samples |
| `../wd/results/genotypes/merged/locityper` | Merged data of the locityper output of all processed samples |

## Helper scripts (`workflow/scripts/helper-scripts/`)

| Path | Description |
|---|---|
| `annotate_gene_coordinates.py` | Looks up genomic start/end coordinates for gene symbols from a list of annotated variants |
| `lookup_gene_names.sh` | Looks up genomic start/end coordinates and chromosome for gene symbols given on the command line |
| `pad_bed.py` | Evenly pads each locus in a bed file to a minimum of 30kb |
| `vcf_sample_overlap.py` | Compares genotypes across a merged VCF containing 3 samples |
| `missing_genotypes_per_sample.sh` | Per-sample count and fraction of missing genotypes in a (multi-sample) VCF, e.g. the PanGenie output |

## Configs (`config/`)

| Path | Description |
|---|---|
| `default_bed/2026-10-22_CHM13.padd20kb-merge10kb.named.bed` | Default set of clustered loci for Locityper usage (copy this file and add own loci as  desired) |
| `default_bed/2026-10-22_CHM13.padd20kb-merge10kb_cluster-content.txt` | List of genes contained in the above clusters |


\
Add info here - be concise, and provide more details in [the workflow documentation](docs/README.md).
# Citation

If not indicated otherwise above, please follow [these instructions](CITATION.md) to cite this repository in your own work.
