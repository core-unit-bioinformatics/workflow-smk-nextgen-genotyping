# KaryoScope read annotation (3rd tool next to PanGenie and locityper)

Adds [KaryoScope](https://github.com/barthel-lab/KaryoScope) (`karyoscope annotate`) to
workflow-smk-nextgen-genotyping as an optional third tool (`tools: "pangenie,locityper,karyoscope"`).
Only `annotate` is integrated for now; `karyoscope karyotype` only accepts assemblies
(read-level input is rejected) and can be decided on later.

Pinned versions:

- KaryoScope **2.3.0** (commit `928be8e`)
- HKS backend **0.4.0** (commit `04bbc52`, as pinned by KaryoScope)
- Database **`HKS_human_CHM13_v2`** v2.0.0 (Zenodo record 21150216, built from T2T-CHM13v2.0)

Files (to be created, see the sections below):

- `karyoscope.def`: Apptainer recipe, built on a machine with internet, `.sif` copied to the server
- `workflow/rules/40-karyotyping/10_karyoscope.smk`: the new module
- `workflow/scripts/karyoscope_db.sh`: database check / download / register
- additions to `00_modules.smk`, `99_aggregate.smk`, `15-init/05_tools.smk` and the parameter file

## What the run does

Short-read FASTQ (downsampled once, outside the workflow) → `karyoscope annotate` against
`HKS_human_CHM13_v2`. Every k-mer of every read is looked up in the database, and
each feature set gets a BED where column 1 is the read (by rank, not by name), columns 2–3
are k-mer offsets **within the read** (not genomic positions) and column 4 is the feature
(e.g. the chromosome of origin, or `novel` if the k-mer isn't in the database).

Per-read BEDs are an intermediate, not a result. The planned result is a per-sample summary
(see [Aggregation](#aggregation-next-step)): how much read sequence each chromosome gets,
normalised to the autosomes, which gives sex (X/Y dosage) and whole-chromosome aneuploidy
QC without alignment.

Result per sample (raw): `results/proc/40-karyotyping/10_karyoscope/ks_annot/<sample>/`
with one `<fastq>.HKS_human_CHM13_v2.<set>.smoothed.bed.gz` per input file and feature set.

## Why the HKS backend

Both backends use the same `karyoscope annotate` call, so the rules are identical; the
backend is chosen by the database. HKS wins on the remaining points:

| | HKS (`HKS_human_CHM13_v2`) | KMC (`KS_human_CHM13_v2`) |
|---|---|---|
| download / extracted | 13.3 GB / 22.7 GB | 16.3 GB / 17.2 GB |
| memory to request | ≥ 16 GB | ≥ 96 GB |
| container build | extra `cargo install` of `hks` | `make` of a bundled C++ helper |
| future | the backend KaryoScope is moving to | to be retired |

With ≥ 96 GB per job, KMC would fit only 1–2 jobs per default-pool node.

## Database handling

The database lives in `local_ref/karyoscope/` (the `--db-root`). KaryoScope only finds
databases listed in `local_ref/karyoscope/installed.json`, so an extracted folder alone
isn't enough; it has to be registered once.

The rule `prepare_karyoscope_database` (a local rule, runs where Snakemake is started)
calls `karyoscope_db.sh`, which goes through these cases in order:

1. **Already registered** → nothing to do.
2. **Extracted folder present but not registered** (copied by hand) → `karyoscope register`.
3. **Tarball present** (`local_ref/karyoscope/HKS_human_CHM13_v2.tar.gz`, copied by hand)
   → check SHA-256, extract, register, delete the tarball.
4. **Nothing present** → `karyoscope download` (needs zenodo.org and raw.githubusercontent.com).
5. **Download fails** → the job stops with instructions for the manual download.

Then it touches `local_ref/karyoscope/HKS_human_CHM13_v2.ready`, which the annotate rules
depend on. Disk: ~36 GB free in `local_ref/` during installation (archive + extracted copy),
~23 GB afterwards.

### Manual download (server without internet, e.g. hilbert)

On any machine with internet:

```bash
curl -L -o HKS_human_CHM13_v2.tar.gz \
    "https://zenodo.org/records/21150216/files/HKS_human_CHM13_v2.tar.gz?download=1"
echo "4da29c348aaf4bc0808adb036c8557827bee798eb306cb0030f351d0a88b977b  HKS_human_CHM13_v2.tar.gz" | sha256sum -c -
rsync -P HKS_human_CHM13_v2.tar.gz <server>:<wd>/local_ref/karyoscope/
```

The next workflow run does the rest (case 3). Alternatively extract on the server and let
case 2 register it:

```bash
cd <wd>/local_ref/karyoscope && tar -xzf HKS_human_CHM13_v2.tar.gz && rm HKS_human_CHM13_v2.tar.gz
```

The reachability test from the login node (both currently time out on hilbert):

```bash
curl -4 -sS --max-time 30 -o /dev/null -w "%{http_code}\n" \
    https://raw.githubusercontent.com/barthel-lab/KaryoScope-registry/main/registry.yaml
curl -4 -sS -L --max-time 30 -r 0-1023 -o /dev/null -w "%{http_code}\n" \
    "https://zenodo.org/records/21150216/files/HKS_human_CHM13_v2.tar.gz?download=1"
```

`200`/`206` = reachable. Once registered, `annotate` doesn't touch the network, so offline
compute nodes are fine.

## Installation

### 1. Build the container (machine with internet and Apptainer)

`karyoscope.def`:

```
Bootstrap: docker
From: condaforge/miniforge3:25.3.1-0

%labels
    karyoscope 2.3.0 (928be8e)
    hks 0.4.0 (04bbc52)

%post
    set -euo pipefail
    apt-get update && apt-get install -y --no-install-recommends git ca-certificates
    rm -rf /var/lib/apt/lists/*

    # KaryoScope + its conda env (htslib, samtools, seqtk, cairo, compilers, rust, ...)
    git clone https://github.com/barthel-lab/KaryoScope.git /opt/KaryoScope
    git -C /opt/KaryoScope checkout 928be8e
    mamba env create -p /opt/ks-env -f /opt/KaryoScope/environment.yml
    mamba install -y -p /opt/ks-env -c conda-forge pandas matplotlib   # for aggregation/plots
    /opt/ks-env/bin/pip install --no-cache-dir /opt/KaryoScope

    # HKS backend, pinned exactly as in the KaryoScope README
    git clone --recurse-submodules https://github.com/jnalanko/HKS.git /opt/HKS
    git -C /opt/HKS checkout 04bbc52
    git -C /opt/HKS submodule update --init --recursive
    cp /opt/KaryoScope/native/hks/Cargo.lock /opt/HKS/Cargo.lock
    PATH=/opt/ks-env/bin:$PATH cargo install --locked --path /opt/HKS --root /opt/ks-env

    rm -rf /opt/HKS /root/.cargo/registry
    mamba clean -afy

%environment
    export PATH=/opt/ks-env/bin:$PATH

%test
    karyoscope version
    hks --version
    samtools --version | head -n 1
```

```bash
apptainer build --fakeroot karyoscope_2.3.0.sif karyoscope.def
apptainer test karyoscope_2.3.0.sif
rsync -P karyoscope_2.3.0.sif <server>:/path/to/containers/
```

### 2. Get the database into `local_ref/karyoscope/`

Either let the workflow download it (server with internet) or copy it by hand
(see [Manual download](#manual-download-server-without-internet-eg-hilbert)).

### 3. Parameter file

```yaml
# Specify which tools to run in the pipeline. Options are: pangenie, locityper, karyoscope
tools: "pangenie,locityper,karyoscope"

# KaryoScope (read-level k-mer annotation)
karyoscope:
  container: /path/to/containers/karyoscope_2.3.0.sif
  database: HKS_human_CHM13_v2
  # SHA-256 of the database tarball (from the KaryoScope registry); used
  # when a hand-copied tarball is found in local_ref/karyoscope/
  database_sha256: 4da29c348aaf4bc0808adb036c8557827bee798eb306cb0030f351d0a88b977b
  # Only shown in the error message for the manual download
  database_url: "https://zenodo.org/records/21150216/files/HKS_human_CHM13_v2.tar.gz?download=1"
  # Feature sets to write; empty = all six (chromosome, region, repeat,
  # subtelomeric, gene, acrocentric). chromosome is enough for dosage QC.
  feature_sets: "chromosome"
```

The SHA-256 is the one listed in the KaryoScope registry for v2.0.0 of the database.

The FASTQ paths in the sample sheet must point to the **downsampled** files. Since PanGenie
and locityper need the full data, KaryoScope runs with its own sample sheet and its own
working directory (`tools: "karyoscope"`). A rough target is 1–2× coverage (~3–6 Gbp per
sample); measure output size and runtime on one sample first.

### 4. Profile

The profile already has `use-apptainer: true`. The container must see the data and the
working directory:

```yaml
apptainer-args: "--bind /pfssmain,/gpfs"
```

## Workflow changes

### `15-init/05_tools.smk`

Add `karyoscope` to the accepted tool names and define `RUN_KARYOSCOPE`, analogous to
`RUN_LOCITYPER`.

### `00_modules.smk`

```python
if RUN_KARYOSCOPE:
    include: "40-karyotyping/10_karyoscope.smk"
```

### `99_aggregate.smk`

```python
if RUN_KARYOSCOPE:
    WORKFLOW_OUTPUT.extend(rules.run_all_karyoscope_annotation.input.annotations)
```

### `workflow/scripts/karyoscope_db.sh`

```bash
#!/usr/bin/env bash
# Make sure a KaryoScope database is installed and registered in DB_ROOT.
# Usage: karyoscope_db.sh DB_ROOT DB_ID SHA256 URL MARKER
set -euo pipefail

db_root=$1
db_id=$2
sha256=$3
url=$4
marker=$5

mkdir -p "${db_root}"
tarball="${db_root}/${db_id}.tar.gz"

is_registered() {
    python3 -c 'import json, pathlib, sys
f = pathlib.Path(sys.argv[1], "installed.json")
sys.exit(0 if f.is_file() and sys.argv[2] in json.loads(f.read_text(encoding="utf-8")).get("databases", {}) else 1)' \
        "${db_root}" "${db_id}"
}

if is_registered; then
    echo "[karyoscope_db] ${db_id} already registered in ${db_root}"
elif [[ -f "${db_root}/${db_id}/manifest.yaml" ]]; then
    echo "[karyoscope_db] ${db_id} found extracted but unregistered, registering"
    karyoscope register "${db_id}" --db-root "${db_root}"
elif [[ -f "${tarball}" ]]; then
    echo "[karyoscope_db] found ${tarball}, checking SHA-256"
    echo "${sha256}  ${tarball}" | sha256sum -c -
    tar -C "${db_root}" -xzf "${tarball}"
    karyoscope register "${db_id}" --db-root "${db_root}"
    rm -f "${tarball}"
elif ! karyoscope download "${db_id}" --db-root "${db_root}" --quiet; then
    cat >&2 <<EOF

[karyoscope_db] ERROR: ${db_id} is not in ${db_root} and could not be downloaded
(no internet access from this machine?).

Download it on a machine with internet access:

    curl -L -o ${db_id}.tar.gz "${url}"

copy ${db_id}.tar.gz into ${db_root}/ and start the workflow again.
See README_karyoscope.md, "Manual download".

EOF
    exit 1
fi

touch "${marker}"
```

### `workflow/rules/40-karyotyping/10_karyoscope.smk`

```python
import pathlib


KARYOSCOPE_CONTAINER = config["karyoscope"]["container"]
KARYOSCOPE_DB_ID = config["karyoscope"]["database"]
KARYOSCOPE_DB_ROOT = DIR_LOCAL_REF.joinpath("karyoscope")
KARYOSCOPE_FEATURE_SETS = [
    fs for fs in str(config["karyoscope"].get("feature_sets", "")).split(",") if fs
]

if not pathlib.Path(KARYOSCOPE_CONTAINER).is_file():
    err_msg = f"Configured karyoscope container is not accessible: {KARYOSCOPE_CONTAINER}"
    logerr(err_msg)
    raise FileNotFoundError(err_msg)

SAMPLES_KARYOSCOPE = [
    sample for sample in SAMPLES
    if classify_sample_input_type(sample, SAMPLE_INPUT_FILES[sample]) not in (None, "cram")
]

if not SAMPLES_KARYOSCOPE:
    err_msg = "Error: no samples are compatible with KaryoScope annotation (need FASTQ input)."
    logerr(err_msg)
    raise ValueError(err_msg)


localrules: prepare_karyoscope_database


rule prepare_karyoscope_database:
    """Check, download or register the KaryoScope database in local_ref/karyoscope."""
    output:
        ready = KARYOSCOPE_DB_ROOT.joinpath(f"{KARYOSCOPE_DB_ID}.ready")
    log:
        DIR_LOG.joinpath("40-karyotyping", "10_karyoscope", "ks_db", f"{KARYOSCOPE_DB_ID}.db.log")
    container:
        KARYOSCOPE_CONTAINER
    params:
        script = get_script("karyoscope_db.sh", extension="sh"),
        db_root = KARYOSCOPE_DB_ROOT,
        db_id = KARYOSCOPE_DB_ID,
        sha256 = config["karyoscope"].get("database_sha256", ""),
        url = config["karyoscope"].get("database_url", "")
    shell:
        "bash {params.script} {params.db_root} {params.db_id} {params.sha256}"
            " '{params.url}' {output.ready} 2>&1 | tee {log}; exit ${{PIPESTATUS[0]}}"


rule run_karyoscope_annotate:
    """Annotate every read of a sample (all its FASTQ files) with 'karyoscope annotate'."""
    input:
        reads = lambda wildcards: SAMPLE_INPUT_FILES[wildcards.sample],
        db_ready = rules.prepare_karyoscope_database.output.ready
    output:
        annot_dir = directory(
            DIR_PROC.joinpath("40-karyotyping", "10_karyoscope", "ks_annot", "{sample}")
        )
    log:
        DIR_LOG.joinpath("40-karyotyping", "10_karyoscope", "ks_annot", "{sample}.annotate.log")
    benchmark:
        DIR_RSRC.joinpath("40-karyotyping", "10_karyoscope", "ks_annot", "{sample}.annotate.rsrc")
    container:
        KARYOSCOPE_CONTAINER
    threads: CPU_MEDIUM
    resources:
        mem_mb=lambda wildcards, attempt: (24 * 1024) * attempt,
        time_hrs=lambda wildcards, attempt: 4 * attempt
    params:
        inputs = lambda wildcards, input: " ".join(f"-i {f}" for f in input.reads),
        feature_sets = " ".join(f"--feature-set {fs}" for fs in KARYOSCOPE_FEATURE_SETS),
        db_root = KARYOSCOPE_DB_ROOT,
        db_id = KARYOSCOPE_DB_ID
    shell:
        "mkdir -p {output.annot_dir} && "
        "karyoscope annotate {params.inputs} -o {output.annot_dir}"
            " --db {params.db_id} --db-root {params.db_root} {params.feature_sets}"
            " --no-keep-presmoothed --no-preserve-order --query-names-sidecar"
            " --threads {threads} &> {log}"


rule run_all_karyoscope_annotation:
    input:
        annotations = expand(
            rules.run_karyoscope_annotate.output.annot_dir,
            sample=SAMPLES_KARYOSCOPE
        )
```

Notes on the `annotate` options:

- `--no-keep-presmoothed`: write only the smoothed BEDs (halves the output).
- `--no-preserve-order`: fastest path; read order doesn't matter for the summary.
- `--query-names-sidecar`: writes read rank → read name per input, so single reads can be
  traced back. R1 and R2 are separate inputs; mate *i* of R1 is mate *i* of R2.
- `--format kst` (karyozip) would shrink the output ~20–40×, but needs karyozip in the
  container. Only worth it if the BED size turns out to be a problem.
- CRAM input is skipped for now (would need `--reference`, like locityper's CRAM branch).

## Aggregation (next step)

Not yet implemented; the format of the per-read BEDs should be checked on one real sample
first. The planned rule `summarize_karyoscope_dosage` reads the `chromosome` BEDs of a sample
and writes one table per sample, then one cohort table
(`results/karyotyping/karyoscope/SAMPLES.chromosome_dosage.tsv`):

- bp of k-mers per chromosome (sum of `end − start` per feature), plus `novel`
- each chromosome relative to the autosomal median (expected ~1.0 for a disomic autosome)
- X and Y relative dosage → inferred sex (XX: X ~1, Y ~0; XY: X ~0.5, Y > 0)
- flags for autosomes far from 1.0 (e.g. ~1.5 = trisomy) and a high `novel` fraction
  (contamination, low quality)

The inferred sex can also be checked against the sample metadata, as a sample-swap test.

## Checks after the first run

- `karyoscope download --status --db-root local_ref/karyoscope` inside the container lists
  `HKS_human_CHM13_v2`.
- Benchmark of one sample (`.rsrc`): memory should stay near the ~10 GB index size; adjust
  `mem_mb`, `time_hrs` and the downsampling target from there.
- Output size per sample, before running the whole cohort.
- The feature names in column 4 of the `chromosome` BED (chromosome naming of CHM13), as
  input for the aggregation script.
