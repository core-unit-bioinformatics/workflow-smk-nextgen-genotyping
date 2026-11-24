# KaryoScope read annotation (3rd tool next to PanGenie and locityper)

Adds [KaryoScope](https://github.com/barthel-lab/KaryoScope) `annotate` to
workflow-smk-nextgen-genotyping as an optional third tool (`tools: "...,karyoscope"`).
Every k-mer of every read is labelled against a k-mer database built from T2T-CHM13v2.0:
chromosome of origin, gene structure, cytogenetic band, 1 Mb bin. The per-read labels are then
condensed into per-sample and cohort tables: chromosome, arm, band and bin dosage, plus a
sex call. `karyoscope karyotype` only accepts assemblies, not reads, and isn't part of this
module.

Pinned versions: KaryoScope **2.3.0** (`928be8e`), HKS backend **0.4.0** (`04bbc52`).
The database (`HKS_CHM13v2_karyo`) is built by the workflow itself, see [Database](#database).

## Files

| File | In the repo |
|---|---|
| `karyoscope.def` | `workflow/containers/karyoscope.def` (recipe only; the `.sif` is not committed) |
| `10_karyoscope.smk` | `workflow/rules/40-karyotyping/10_karyoscope.smk` |
| `karyoscope_summarize.py` | `workflow/scripts/karyoscope/` |
| `karyoscope_db.sh` | `workflow/scripts/karyoscope/` (register a database that is present) |
| `karyoscope_fetch_source.sh` | `workflow/scripts/karyoscope/` (download one build source) |
| `karyoscope_build_db.sh` | `workflow/scripts/karyoscope/` (build the database) |
| `karyoscope_feature_beds.py` | `workflow/scripts/karyoscope/` (arm level for the cytobands, bins) |
| `fetch_reference_reads.sh` | `workflow/scripts/karyoscope/` (not run by the workflow: download reference genomes' reads) |
| `reference_values.HKS_CHM13v2_karyo.tsv` | `workflow/resources/karyoscope/` (made once, see [Reference values](#reference-values)) |
| `README.md` | `docs/karyoscope/README.md` (this file) |

KaryoScope is wired in through `15-init/05_tools.smk` (`RUN_KARYOSCOPE`), `00_modules.smk`
and `99_aggregate.smk`. The PBS profile stays unchanged; the bind path goes on the command line.

## What the run does

```
first run only (database not present):
  fetch_karyoscope_source      local rule, per source file: download, or use the file that is there
  build_karyoscope_database    cluster job (~80 GB RAM): build + register the database
database already present (folder or tarball in local_ref/karyoscope/):
  prepare_karyoscope_database  local rule: register, check the feature sets
                               (no job at all once the database is registered and marked ready)

per sample (FASTQ, downsampled):
  run_karyoscope_annotate      one smoothed BED per FASTQ and feature set
  summarize_karyoscope_sample  annotated bp per label and feature set
cohort:
  merge_karyoscope_cohort      composition and dosage tables
```

## Feature sets

| Set | Default | Labels |
|---|---|---|
| `chromosome` | yes | `chr1` … `chrY`; group labels (`acrocentric`, `autosome`, `sex`, …) for k-mers shared between chromosomes |
| `gene` | yes | `exon`, `intron`, `intergenic` |
| `cytoband` | yes | bands (`5q31.2`), band groups (`5q31`), arms (`5q`), chromosomes (`5`) |
| `bins_1mb` | yes | fixed 1 Mb bins, `chr5_131000000_132000000` |
| `region` | no | `p_arm`, `q_arm`, centromeric satellites (`hor`, `hsat2`, `hsat3`, `bsat`, `rDNA`, …) |

Every set can also give `novel` (k-mer not in CHM13: errors, private variants,
contamination) and `none` (chrM).

Labels are hierarchical. A k-mer that occurs in only one band gets that band. One shared
between bands of the same arm gets the band group or the arm, between arms the chromosome,
between chromosomes `categorized`. The `chromosome` hierarchy groups chromosomes by
centromere position (metacentric, submetacentric, acrocentric, sex).

**Choosing feature sets:** the defaults are `karyoscope.default_features` in the parameter
file (built-in: `chromosome,gene,cytoband,bins_1mb`). `karyo-features` adds more, in the
parameter file or on the command line:

```bash
snakemake ... --config karyo-features=region
```

Any name works as long as the database has that set. The workflow checks this at startup
and stops with the list of available sets if not. The summary needs:

| Table | Needs |
|---|---|
| chromosome dosage, sex call | `chromosome` |
| arm and band dosage | `cytoband` |
| bin dosage | a `bins_*` set |

If one of these sets is not annotated, the workflow warns at startup and in the merge log,
and skips that table; the rest is produced as usual.

## Outputs

All in `results/karyotyping/karyoscope/`:

| File | Content |
|---|---|
| `SAMPLES.chromosome_dosage.tsv` | per sample: copies per autosome, X and Y, sex call, flags |
| `SAMPLES.arm_dosage.tsv` | per sample: copies per arm (incl. X and Y), flags |
| `SAMPLES.cytoband_dosage.tsv` | long format, per sample and band: copies, flag |
| `SAMPLES.bins_1mb_dosage.tsv` | long format, per sample and bin: start, end, copies, flag |
| `SAMPLES.reference_values.tsv` | the expected values used as baseline in this run (see [Reference values](#reference-values)) |
| `SAMPLES.<set>.composition.tsv` | per feature set (not cytoband/bins): sample × label, fraction of annotated bp |

Per sample: `<proc>/40-karyotyping/10_karyoscope/ks_sum/<sample>.composition.tsv` (long
format: set, label, bp, fraction) and the raw per-read BEDs in `.../ks_annot/<sample>/`. The
raw BEDs are large (each feature set adds roughly one BED of the size of the `chromosome`
one). With `keep_read_annotations: false` they're `temp()` and get deleted once the sample is
summarized.

Labels are sorted by hierarchy (`chromosome`: `categorized`, `autosome`, `metacentric`,
`submetacentric`, `acrocentric`, `chr1` … `chr22`, `sex`, `chrX`, `chrY`; `gene`: `exon`,
`intron`, `intergenic`) or genomically (bands from the p-arm telomere through the centromere
to the q-arm telomere; bins by position). `novel` comes last.

### How the copy numbers work

- **share**: bp of a label divided by the autosomal bp *of the same feature set* (labels
  on chr1–22, group labels within a chromosome included). Independent of sequencing depth.
- **copies** = expected copies × sample share / expected share. The expected share is what a
  normal genome shows for that label: autosomes 2 copies, chrX 2 copies (taken from female
  references), chrY 1 copy (from male references). So a female shows ~2 X copies and ~0 Y,
  a male ~1 X and ~1 Y, a trisomy 21 ~3 copies of chr21.
- **flag / flags**: `loss` / `gain` (or `5q:1.02`) where the copies deviate from the expected
  copies by more than `max_deviation` (default 0.2, i.e. below 1.6 or above 2.4 for
  autosomes). Only autosomes are flagged; X/Y are covered by the sex call.

Where the expected shares come from, in order of preference:

1. `karyoscope.reference_samples` (or `--config karyo-reference-samples=A,B,C`): normal
   samples in the same run, e.g. matched normals.
2. The reference values file (`karyoscope.reference_values`, default
   `workflow/resources/karyoscope/reference_values.<database>.tsv`), derived once from
   public normal genomes, see [Reference values](#reference-values).
3. Neither: the median of all samples of the run, with a warning. Then the copies only say
   "relative to this cohort", and alterations shared by many samples partly cancel out.

Limits: tumour purity and subclonality dilute the signal (50 % tumour cells and one lost
arm give ~1.5 copies instead of 1); copy-neutral loss of heterozygosity is invisible (counts
only, no alleles); there is no GC correction, so single bins are noisier than arms, and data
from a different lab than the reference can shift single chromosomes slightly (e.g. 1.95 or
2.05). Whole chromosomes and arms are robust; single bands and bins are best read as runs of
neighbouring bins.

**`SAMPLES.chromosome_dosage.tsv`**:

| Column | Meaning |
|---|---|
| `total_bp` | annotated k-mer bp in the `chromosome` set, all labels |
| `autosomal_bp`, `autosomal_fraction` | bp labelled `chr1`–`chr22` exactly (no group labels), and their share of `total_bp` |
| `novel_fraction` | share of `novel`; high values point to contamination or poor quality |
| `chr1_copies` … `chr22_copies` | copies per autosome |
| `chrX_copies` | ~2 for XX, ~1 for XY |
| `chrY_copies` | ~0 for XX, ~1 for XY |
| `sex_chromosomes` | X copies rounded (at most 0.25 off a whole number), Y present from 0.5 copies, absent up to 0.1: `XX`, `XY`, `X0`, `XXY`, `XXX`, … or `ambiguous` (e.g. Y between 0.1 and 0.5: mosaic loss of Y) |
| `inferred_sex` | `female` (XX), `male` (XY), `atypical`, `ambiguous` |
| `flags` | autosomes off by more than `max_deviation` (e.g. `chr8:2.91`), plus `sex:<call>(...)` for anything other than XX/XY |

The sex call works on these copies. Without reference values (or with a reference lacking
females or males), it falls back to rough built-in values for chrX and chrY; these also sort
the reference samples into females and males when reference values are derived.

**`SAMPLES.arm_dosage.tsv`**: one `<arm>_copies` column per arm (`1p_copies` …
`Yq_copies`), `flags` (e.g. `5q:1.02;17p:1.24`). An arm's value sums its bands, band groups
and the arm label itself. The short arms of the acrocentric chromosomes (13p, 14p, 15p, 21p,
22p) are mostly rDNA and satellites, which vary a lot between people anyway.

**`SAMPLES.cytoband_dosage.tsv`**: `sample`, `chrom`, `arm`, `band`, `copies`, `flag`. Rows with a band-group label (`5q31`) hold k-mers that could only be placed to that
group.

**`SAMPLES.bins_1mb_dosage.tsv`**: `sample`, `chrom`, `start`, `end`, `copies`, `flag`. The last bin of each chromosome is shorter.

Arm, band and bin tables answer different questions: the arm table gives the overview, the
band table names the affected region in cytogenetic terms (e.g. 5q31–q33), the bin table
shows where within an arm the change starts and ends.

## Reference values

The expected share of every label (chromosome, arm, band, bin) can't be computed from the
reference sequence alone: how many of a region's k-mers end up with exactly that label
depends on its repeats, duplications and on how real reads behave. So it's measured once on
real sequencing data of normal genomes, and stored as
`workflow/resources/karyoscope/reference_values.<database>.tsv`. Every later run uses it,
so copies don't depend on what else is in the run.

The file is tied to the database (`# database:` line). After building a new database (e.g.
another bin size), derive it again.

### Deriving them (once per database)

Reference genomes: 8 unrelated individuals from the 1000 Genomes 30x data (NYGC, Illumina
NovaSeq 2×150), 4 female and 4 male, 4 populations:

| Sample | Sex | Population |
|---|---|---|
| NA12891 / NA12892 | M / F | CEU (Utah, European ancestry) |
| NA19239 / NA19238 | M / F | YRI (Yoruba, Nigeria) |
| HG00512 / HG00513 | M / F | CHS (Southern Han Chinese) |
| HG00731 / HG00732 | M / F | PUR (Puerto Rico) |

Several individuals from several populations average out individual variation; both sexes
are needed for the X and Y values.

**1. On a machine with internet**, stream 20 million read pairs (~2× coverage, like the
downsampled data) per sample from ENA:

```bash
bash workflow/scripts/karyoscope/fetch_reference_reads.sh karyoscope_reference_reads
# optional: read pairs and own sample list
# bash .../fetch_reference_reads.sh OUTDIR 20000000 NA12891 NA12892 ...
```

This writes `<sample>_R1.fq.gz` / `_R2.fq.gz` (~1.5 GB each) and
`sample_sheet_reference.tsv`. Only the first 20 M read pairs are downloaded (FASTQ order
follows the flowcell, not the genome, so this is a random subsample).

**2. Copy them to the server** and replace the local folder in the sample sheet's paths
with the folder on the server:

```bash
rsync -P karyoscope_reference_reads/ <server>:/path/to/karyoscope_reference_reads/
# on the server:
sed -i 's|<local folder printed by the script>|/path/to/karyoscope_reference_reads|g' \
    /path/to/karyoscope_reference_reads/sample_sheet_reference.tsv
```

**3. Run the workflow** with these samples as reference samples, in its own working
directory:

```bash
snakemake -d <reference_wd> ... --config samples=/path/to/karyoscope_reference_reads/sample_sheet_reference.tsv \
    tools=karyoscope \
    karyo-reference-samples=NA12891,NA12892,NA19239,NA19238,HG00512,HG00513,HG00731,HG00732 \
    ... "$BIND"
```

**4. Check** `results/karyotyping/karyoscope/SAMPLES.chromosome_dosage.tsv`: 4 × `XX`,
4 × `XY`, all autosomes ~2.0 copies (they're compared with their own median, so this mainly
catches an outlier sample). Then copy the reference values into the repo and commit them:

```bash
cp <reference_wd>/results/karyotyping/karyoscope/SAMPLES.reference_values.tsv \
   workflow/resources/karyoscope/reference_values.HKS_CHM13v2_karyo.tsv
```

From then on every run without `reference_samples` uses this file; the log says
`KaryoScope baseline: reference values ...`.

## Database

The workflow uses its own database, `HKS_CHM13v2_karyo` (`karyoscope.database`), with the
feature sets `chromosome`, `region`, `gene` (all three following KaryoScope's CHM13 recipe),
`cytoband` (T2T-CHM13 cytobands, with an added arm level) and `bins_1mb`. The official
`HKS_human_CHM13_v2` lacks `cytoband` and bins, and its `repeat`, `acrocentric` and
`subtelomeric` sets are not part of this one.

At startup, the workflow checks `local_ref/karyoscope/`:

1. database registered in `installed.json` → use it
2. folder `HKS_CHM13v2_karyo/` or tarball `HKS_CHM13v2_karyo.tar.gz` present →
   `prepare_karyoscope_database` registers it (checks `database_sha256` if set)
3. nothing present → build it:
   - `fetch_karyoscope_source` downloads each missing source file into
     `local_ref/karyoscope/sources/`. Without internet it stops and prints the `curl` command
     and the target path. Files that are already there are used as they are.
   - `build_karyoscope_database` (cluster job in the container) builds and registers it.

In every case it then checks that the database has all selected feature sets.

### Building on a server without internet

**1. On a machine with internet**, download the four source files (~1 GB in total):

```bash
mkdir karyoscope_sources && cd karyoscope_sources
curl -L -o chm13v2.0.fa.gz \
  https://s3-us-west-2.amazonaws.com/human-pangenomics/T2T/CHM13/assemblies/analysis_set/chm13v2.0.fa.gz
curl -L -o chm13v2.0.cenSatv2.1.bed \
  https://raw.githubusercontent.com/hloucks/CenSatData/refs/heads/main/CHM13/chm13v2.0.cenSatv2.1.bed
curl -L -o CHM13.gtf.gz \
  https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/009/914/755/GCF_009914755.1_T2T-CHM13v2.0/GCF_009914755.1_T2T-CHM13v2.0_genomic.gtf.gz
curl -L -o chm13v2.0_cytobands_allchrs.bed \
  https://s3-us-west-2.amazonaws.com/human-pangenomics/T2T/CHM13/assemblies/annotation/chm13v2.0_cytobands_allchrs.bed

sha256sum -c - <<'EOF'
c6f35d83e4b28f33807c2f65df76b78444f246aa9fb82a3c262bde35e6a6a78c  chm13v2.0.cenSatv2.1.bed
a72e1bc4a219b35cdde0f56c3a1333c4137e72e751390dfe30e2046ef115863e  CHM13.gtf.gz
EOF
head -3 chm13v2.0_cytobands_allchrs.bed    # chr1  0  ...  p36.33  gneg
```

The FASTA's sequence content is checked during the build. The file names must stay exactly
as above.

**2. Copy them to the server**, into the working directory's `local_ref/karyoscope/sources/`:

```bash
rsync -P karyoscope_sources/* <server>:<wd>/local_ref/karyoscope/sources/
```

**3. Start the workflow as usual.** The dry run should list `fetch_karyoscope_source` ×4
(they only see that the files are there) and `build_karyoscope_database` ×1. To build only
the database:

```bash
snakemake --profile <profile> --configfile <params>.yaml "$BIND" \
    --until build_karyoscope_database
```

Build job (`build_karyoscope_database`): 16 threads, 128 GB, 4 h, set in the rule like all
other resources. KaryoScope measured ~20 min and ~80 GB peak for a comparable CHM13 build.
On a machine with little RAM, `karyoscope_build_db.sh` takes an optional last argument, a
scratch directory for HKS's external-memory mode (~6× less memory, ~1.4× the time). Disk:
~60 GB free in `local_ref/karyoscope/` during the build, ~25 GB afterwards. The build log is
`log/40-karyotyping/10_karyoscope/ks_db/HKS_CHM13v2_karyo.build.log`; the small build inputs
(spec, hierarchies) stay in `local_ref/karyoscope/HKS_CHM13v2_karyo/build_inputs/`.

On a server with internet, step 3 alone is enough: the sources are downloaded automatically.

The old `HKS_human_CHM13_v2` can stay in `local_ref/karyoscope/` (it's simply not used) or be
deleted, together with its entry in `installed.json`. To use it anyway, set
`database: HKS_human_CHM13_v2` and `default_features: "chromosome,gene"` (arm, band and bin
tables are then skipped).

## Container

The container can't be built on the server: the build pulls the base image from Docker Hub,
the sources from GitHub, the Rust crates for `hks` from crates.io and a package from PyPI.
Build it on a machine with internet and Apptainer:

```bash
sudo apptainer build karyoscope_2.3.0.sif workflow/containers/karyoscope.def   # or --fakeroot
apptainer test karyoscope_2.3.0.sif
rsync -P karyoscope_2.3.0.sif <server>:/path/to/containers/
```

It contains everything the database build needs as well (`karyoscope build`, `hks`,
`samtools`, `bgzip`, and KaryoScope's recipe files under `/opt/KaryoScope`).

## Parameter file

```yaml
# KaryoScope feature sets to annotate IN ADDITION to the defaults
# (karyoscope.default_features). Comma-separated, empty = none.
# This can also be set via --config karyo-features=... on the CLI instead
karyo-features: ""

# KaryoScope (read-level k-mer annotation)
karyoscope:
  # local .sif, or a registry URI Snakemake pulls itself (oras://..., server with internet)
  container: /path/to/containers/karyoscope_2.3.0.sif
  # database id in local_ref/karyoscope/; built by the workflow if not present
  database: HKS_CHM13v2_karyo
  # optional: checked when a hand-copied tarball <database>.tar.gz is found
  database_sha256: ""
  # always-annotated feature sets; the summary needs chromosome (chromosome
  # dosage, sex), cytoband (arm and band dosage) and bins_1mb (bin dosage)
  default_features: "chromosome,gene,cytoband,bins_1mb"
  # bin size of the bins_<N>mb feature set (database build only)
  bin_size_mb: 1
  # keep the large per-read BEDs after summarizing (false = temp())
  keep_read_annotations: true
  # baseline for the copy numbers: normal samples of this run (e.g. matched
  # normals); also --config karyo-reference-samples=A,B. Empty: use the
  # reference values file below
  reference_samples: ""
  # expected values of normal genomes (see "Reference values"); default:
  # workflow/resources/karyoscope/reference_values.<database>.tsv
  # reference_values: /path/to/reference_values.tsv
  # flag copies that deviate from the expected copies by more than this
  # fraction (0.2: autosomes below 1.6 or above 2.4)
  max_deviation: 0.2
```

`bin_size_mb: 1` makes the bin set `bins_1mb`; another size gives e.g. `bins_5mb` (then also
change `default_features`, and build a new database or give it a new `database` id).

## Running

KaryoScope uses **downsampled** FASTQs (~1–2× coverage), while PanGenie and locityper need
the full data, so it runs in its own working directory with its own sample sheet and
`--config tools=karyoscope`. File names must end in `.fq.gz`/`.fastq.gz`: KaryoScope decides
by the extension whether an input is reads, and treats anything else as an assembly (all
read names in memory, which runs out of memory on WGS).

The container sees the working directory automatically. Everything else (FASTQs, and the
repo with the scripts when Snakemake runs with `-d`) needs a bind path on the command line.
On hilbert, Apptainer comes as a module:

```bash
module load apptainer/1.2.5
BIND='--apptainer-args=--bind /gpfs/project/projects/medbioinf'

snakemake -n --profile <profile> --configfile <params>.yaml --config tools=karyoscope "$BIND"
snakemake    --profile <profile> --configfile <params>.yaml --config tools=karyoscope "$BIND"
```

Resources per sample (`run_karyoscope_annotate`): `CPU_MEDIUM` threads, 24 GB (HKS keeps a
~10 GB index in memory), 24 h; `summarize_karyoscope_sample` 12 h; both scaled per attempt.
These are sized for full-depth test samples; set them from the `.rsrc` benchmarks once the
real (downsampled) data has run.

## Checks after the first cohort

- `inferred_sex` against the sample metadata (also a sample-swap test). `ambiguous` with
  `chrY_copies` between 0.1 and 0.5 is usually mosaic loss of Y (common in older men).
- Autosome and arm copies of normal samples should sit within ~±0.1 of 2. If they're
  noisier, the downsampling is too strong; if single chromosomes are shifted in all samples,
  the lab differs a lot from the reference data (use normal samples of the run as
  `reference_samples`).
- `novel_fraction` outliers: contamination or low quality.

## Moving to another server

The KaryoScope rules use no conda envs and no wrappers, only the container. A new server
needs Snakemake, Apptainer (compute nodes and the node Snakemake runs on), the `.sif` and
`local_ref/karyoscope/` (copy as is; `installed.json` stores the database folder relative to
its root). It needs no internet and no conda mirror. Then adjust `karyoscope.container`, the
sample sheet paths, the profile (absolute script paths, account) and the `--bind` paths.
If finished results move along, run once with `--rerun-triggers mtime` so changed paths in
`params` don't trigger reruns.

On a server with internet, the container can also come from a registry. Push it once with
`apptainer push karyoscope_2.3.0.sif oras://ghcr.io/<user>/karyoscope:2.3.0` and set
`container: oras://ghcr.io/<user>/karyoscope:2.3.0`. Snakemake pulls it on the first run.
