# KaryoScope read annotation (3rd tool next to PanGenie and locityper)

Adds [KaryoScope](https://github.com/barthel-lab/KaryoScope) `annotate` to
workflow-smk-nextgen-genotyping as an optional third tool (`tools: "...,karyoscope"`).
Every k-mer of every read is labelled against a k-mer database built from T2T-CHM13v2.0.
The per-read labels are then condensed into per-sample and cohort tables. `karyoscope karyotype`
only accepts assemblies, not reads, and isn't part of this module.

Pinned versions: KaryoScope **2.3.0** (`928be8e`), HKS backend **0.4.0** (`04bbc52`),
database **`HKS_human_CHM13_v2`** v2.0.0 (Zenodo record 21150216).

## Files

| File in this package | Goes to (in the repo) |
|---|---|
| `karyoscope.def` | `workflow/containers/karyoscope.def` (recipe only; the `.sif` is not committed) |
| `10_karyoscope.smk` | `workflow/rules/40-karyotyping/10_karyoscope.smk` |
| `karyoscope_db.sh` | `workflow/scripts/karyoscope/karyoscope_db.sh` |
| `karyoscope_summarize.py` | `workflow/scripts/karyoscope/karyoscope_summarize.py` |
| `README.md` | `docs/karyoscope/README.md` (this file) |

Plus small edits to `15-init/05_tools.smk`, `00_modules.smk`, `99_aggregate.smk` and the
parameter file (step 3). The PBS profile stays unchanged; the bind path goes on the command
line (step 5).

## What the run does

```
FASTQ (downsampled, R1 + R2)
  └─ prepare_karyoscope_database   once, local rule: check / register / download the DB
  └─ run_karyoscope_annotate       per sample: one smoothed BED per FASTQ and feature set
  └─ summarize_karyoscope_sample   per sample: annotated bp per label and feature set
  └─ merge_karyoscope_cohort       cohort tables
```

### Feature sets

`chromosome` and `gene` are always annotated. More sets can be added in the parameter file
or on the command line (`tools` works the same way):

```bash
snakemake ... --config karyo-features=region,repeat
```

| Set | Labels |
|---|---|
| `chromosome` (default) | `chr1` … `chrY`; group labels (`acrocentric`, `autosome`, `sex`, …) for k-mers shared between chromosomes |
| `gene` (default) | `exon`, `intron`, `intergenic` |
| `region` | `p_arm`, `q_arm`, centromeric satellites (`hor`, `hsat2`, `hsat3`, `bsat`, `rDNA`, …) |
| `repeat` | RepeatMasker class (`LINE`, `SINE`, `LTR`, `Satellite`, …, `nonrepeat`) |
| `acrocentric`, `subtelomeric` | features of the acrocentric short arms / chromosome ends |

Every set can also give `novel` (k-mer not in CHM13: errors, private variants,
contamination) and `none` (chrM).

### Outputs

| Path | Content |
|---|---|
| `results/karyotyping/karyoscope/SAMPLES.chromosome_dosage.tsv` | main QC table, see below |
| `results/karyotyping/karyoscope/SAMPLES.<set>.composition.tsv` | per feature set: sample × label, fraction of annotated bp |
| `<proc>/40-karyotyping/10_karyoscope/ks_sum/<sample>.composition.tsv` | per sample, long format (set, label, bp, fraction) |

Labels are sorted by the database hierarchy in all tables: `chromosome` as `categorized`,
`autosome`, `metacentric`, `submetacentric`, `acrocentric`, `chr1` … `chr22`, `sex`, `chrX`,
`chrY`, `novel`; `gene` as `exon`, `intron`, `intergenic`, `novel`. Other feature sets are
alphabetical, with `none` and `novel` last.
| `<proc>/40-karyotyping/10_karyoscope/ks_annot/<sample>/` | raw per-read BEDs (`<fastq stem>.HKS_human_CHM13_v2.<set>.smoothed.bed.gz`) |

The raw BEDs are large. With `keep_read_annotations: false` they're `temp()` and get
deleted once the sample is summarized.

**`SAMPLES.chromosome_dosage.tsv`** columns:

| Column | Meaning |
|---|---|
| `total_bp` | annotated k-mer bp in the `chromosome` set, all labels |
| `autosomal_bp`, `autosomal_fraction` | bp labelled `chr1`–`chr22` exactly (no group labels), and their share of `total_bp` |
| `novel_fraction` | share of `novel`; high values point to contamination or poor quality |
| `chr1` … `chr22` | the chromosome's share of `autosomal_bp`, divided by the cohort median. ~1.0 = normal, ~1.5 = trisomy, ~0.5 = monosomy |
| `chrX_ppm` | chrX bp per million `autosomal_bp` (not cohort-normalised, unlike `chr1`…`chr22`) |
| `chrX_copies` | estimated X copies: `2 × chrX_ppm / x_diploid_ppm` (~2 for XX, ~1 for XY) |
| `chrY_ppm` | chrY bp per million `autosomal_bp` |
| `chrY_copies` | estimated Y copies: `chrY_ppm / y_haploid_ppm` (~0 for XX, ~1 for XY); display only until `y_haploid_ppm` is calibrated |
| `sex_chromosomes` | from rounded `chrX_copies` and the Y ppm thresholds (Y present ≥ `male_y_ppm`, absent ≤ `female_y_ppm`, else ambiguous): `XX`, `XY`, `X0`, `XXY`, `XXX`, … or `ambiguous` |
| `inferred_sex` | `female` (XX), `male` (XY), `atypical` (any other combination), `ambiguous` |
| `flags` | autosomes deviating from 1 by more than `max_deviation`, plus `sex:<call>(...)` for anything other than XX/XY; `.` = none |

All values are fractions, so they don't depend on sequencing depth. X and Y use the same
denominator (`autosomal_bp`) as the autosome shares, so the sex call works per sample and
doesn't depend on the cohort's sex ratio. The autosome ratios use the **cohort median** as
the baseline, so they need several samples (warning below 5) and assume most samples are
normal. `x_diploid_ppm` (53000) comes from the chrX/autosome length ratio of CHM13 and the
first female test sample (52745); check it and the Y thresholds on the first cohort (step 6).

## Step 1: container and database (machine with internet)

The container can't be built on the server: the build pulls the base image from Docker Hub,
the sources from GitHub, the Rust crates for `hks` from crates.io and a package from PyPI.
A git or conda mirror doesn't cover that. Build it on your Ubuntu machine with Apptainer:

```bash
sudo apptainer build karyoscope_2.3.0.sif workflow/containers/karyoscope.def   # or --fakeroot
apptainer test karyoscope_2.3.0.sif
```

If the base image tag `26.7.2-1` isn't found, use any current `condaforge/miniforge3` tag.

Download and verify the database (13.3 GB):

```bash
curl -L -o HKS_human_CHM13_v2.tar.gz \
    "https://zenodo.org/records/21150216/files/HKS_human_CHM13_v2.tar.gz?download=1"
echo "4da29c348aaf4bc0808adb036c8557827bee798eb306cb0030f351d0a88b977b  HKS_human_CHM13_v2.tar.gz" \
    | sha256sum -c -
```

Copy both to the server:

```bash
rsync -P karyoscope_2.3.0.sif <server>:/path/to/containers/
rsync -P HKS_human_CHM13_v2.tar.gz <server>:<wd>/local_ref/karyoscope/
```

## Step 2: add the files to the repo (branch `feature-karyoscope`)

```bash
git switch feature-karyoscope
# copy the files from the table above, then do the edits in step 3
git add workflow/ docs/karyoscope/
git commit -m "Add KaryoScope read annotation module"
git push            # upstream is "all": GitHub + GitLab
```

On the server: `git pull`.

## Step 3: edits to existing files

### `15-init/05_tools.smk`

`karyoscope` is added to `_AVAILABLE_TOOLS` and `RUN_KARYOSCOPE` is defined. Without a
`tools` parameter the default stays `pangenie,locityper`: KaryoScope is opt-in, because it
fails without a configured container.

### `00_modules.smk`

```python
if RUN_KARYOSCOPE:
    include: "40-karyotyping/10_karyoscope.smk"
```

### `99_aggregate.smk`

```python
if RUN_KARYOSCOPE:
    WORKFLOW_OUTPUT.extend(rules.run_all_karyoscope_annotation.input.summary)
```

### Parameter file

```yaml
# Specify which tools to run in the pipeline. Options are: pangenie, locityper, karyoscope
tools: "karyoscope"

# KaryoScope feature sets to annotate IN ADDITION to chromosome and gene.
# Options: region, repeat, acrocentric, subtelomeric (comma-separated, empty = none)
# This can also be set via --config karyo-features=... on the CLI instead
karyo-features: ""

# KaryoScope (read-level k-mer annotation)
karyoscope:
  # local .sif, or a registry URI Snakemake pulls itself (oras://..., server with internet)
  container: /path/to/containers/karyoscope_2.3.0.sif
  database: HKS_human_CHM13_v2
  # checked when a hand-copied tarball is found in local_ref/karyoscope/
  database_sha256: 4da29c348aaf4bc0808adb036c8557827bee798eb306cb0030f351d0a88b977b
  # shown in the error message for a manual download
  database_url: "https://zenodo.org/records/21150216/files/HKS_human_CHM13_v2.tar.gz?download=1"
  # keep the large per-read BEDs after summarizing (false = temp())
  keep_read_annotations: true
  # sex call, part 1 - Y: chrY bp per million autosomal bp
  # >= male_y_ppm: Y present; <= female_y_ppm: Y absent; in between: ambiguous
  male_y_ppm: 1000
  female_y_ppm: 500
  # sex call, part 2 - X: expected chrX ppm of autosomal bp for TWO X copies
  # (chrX_copies = 2 * chrX_ppm / x_diploid_ppm); a copy estimate further
  # than x_copy_tolerance from a whole number is called ambiguous
  x_diploid_ppm: 53000
  x_copy_tolerance: 0.25
  # expected chrY ppm of autosomal bp for ONE Y copy, only used for the
  # chrY_copies column (the Y part of the sex call uses the ppm thresholds);
  # rough estimate - set it to chrY_ppm of the first confirmed XY sample
  y_haploid_ppm: 3500
  # flag an autosome whose ratio to the cohort median deviates by more than this
  max_deviation: 0.2
```


## Step 4: database on the server

Nothing to do by hand if the tarball is in `local_ref/karyoscope/`. On the first run,
`prepare_karyoscope_database` goes through these steps:

1. registered in `local_ref/karyoscope/installed.json` → done
2. extracted folder `local_ref/karyoscope/HKS_human_CHM13_v2/` present → register
3. tarball present → check SHA-256, extract, register, delete the tarball
4. nothing present → `karyoscope download` (only works with internet)
5. download fails → stops with the curl command and the target folder

It then touches `local_ref/karyoscope/HKS_human_CHM13_v2.ready`. This is a local rule, so it
runs on the node Snakemake is started from, which also needs Apptainer. Disk: ~36 GB free
during extraction, ~23 GB afterwards. KaryoScope only uses databases listed in
`installed.json`, so a folder that is only extracted gets registered in step 2.

## Step 5: sample sheet and run

KaryoScope uses the **downsampled** FASTQs, while PanGenie and locityper need the full data.
So run it in its own working directory with its own sample sheet (same format, downsampled
paths) and `tools: "karyoscope"`.

Before that, fix two things in the current enable sheet:

- `K304-KB0273c_R1.fq_downsample.gz` doesn't end in `.fq.gz`. KaryoScope decides by the
  extension whether an input is reads. Otherwise it treats the file as an assembly and keeps
  every read name in memory, which runs out of memory on WGS. Rename it
  (`..._R1_downsample.fq.gz`, like the other samples).
- `68155` lists `_R1` twice.

The container only sees the working directory (bound by default) and what is bound
explicitly. The FASTQs (and anything else outside the working directory) need a bind path.
It goes on the command line, so the profile stays unchanged. `use-apptainer: true` is
already in the profile.

```bash
BIND='--apptainer-args=--bind /pfssmain'   # comma-separated for several roots

# 1. dry run: only KaryoScope rules, no conda env creation
snakemake -n --profile <profile> --configfile <params>.yaml "$BIND"

# 2. database only
snakemake --profile <profile> --configfile <params>.yaml "$BIND" \
    --until prepare_karyoscope_database

# 3. one sample, to measure runtime, memory and output size
snakemake --profile <profile> --configfile <params>.yaml "$BIND" \
    <proc>/40-karyotyping/10_karyoscope/ks_sum/40936.composition.tsv

# 4. everything
snakemake --profile <profile> --configfile <params>.yaml "$BIND"
```

`--apptainer-args "--bind /pfssmain"` (with a space) works too; the `=` form is just the one
that can't be misread as a separate option.

Resources per sample (`run_karyoscope_annotate`): `CPU_MEDIUM` threads, 24 GB (HKS keeps a
~10 GB index in memory), 6 h, both scaled per attempt. Adjust these after the benchmark of the
test sample (`<rsrc>/40-karyotyping/10_karyoscope/ks_annot/40936.annotate.rsrc`). A rough
downsampling target is 1–2× coverage (~3–6 Gbp per sample).

## Step 6: checks after the first cohort

- `inferred_sex` against the sample metadata (also a sample-swap test). If samples end up
  `ambiguous`: plot `chrY_ppm` (log scale) and set `male_y_ppm` / `female_y_ppm` between the
  two clusters; check that `chrX_copies` clusters around 1 and 2, otherwise adjust
  `x_diploid_ppm` to the median `chrX_ppm` of the confirmed females. Set
  `y_haploid_ppm` to the median `chrY_ppm` of the confirmed males.
- Autosome ratios of normal samples should sit within ~±0.05 of 1. If they're noisier, the
  downsampling is too strong.
- `novel_fraction` outliers: contamination or low quality.

## Moving to another server

The KaryoScope rules use no conda envs and no wrappers, only the container. A new server
needs Snakemake, Apptainer (compute nodes and the node Snakemake runs on), the `.sif` and
`local_ref/karyoscope/` (copy as is; `installed.json` stores the DB folder relative to the DB
root). It needs no internet and no conda mirror. Then adjust `karyoscope.container`, the
sample sheet paths, the profile (absolute script paths, account) and the `--bind` paths on
the command line.
If finished results move along, run once with `--rerun-triggers mtime` so changed paths in
`params` don't trigger reruns.

On a server with internet, the container can also come from a registry. Push it once with
`apptainer push karyoscope_2.3.0.sif oras://ghcr.io/<user>/karyoscope:2.3.0` and set
`container: oras://ghcr.io/<user>/karyoscope:2.3.0`. Snakemake pulls it on the first run.