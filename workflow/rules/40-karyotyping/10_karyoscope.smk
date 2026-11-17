"""
KaryoScope read annotation (3rd tool next to PanGenie and locityper).

Every k-mer of every read is labelled against the KaryoScope database
(chromosome of origin, gene structure, ...); the per-read BEDs are then
condensed into per-sample and cohort tables (composition per feature set,
chromosome dosage, inferred sex).

All rules run in the KaryoScope Apptainer image (config: karyoscope.container);
no conda env is used. See docs/karyoscope/README.md.
"""

import pathlib


KARYOSCOPE_FEATURE_SETS_ALL = [
    "chromosome", "region", "repeat", "gene", "acrocentric", "subtelomeric"
]
# Always annotated; 'chromosome' is required for the dosage table
KARYOSCOPE_FEATURE_SETS_DEFAULT = ["chromosome", "gene"]

_KS_CONFIG = config.get("karyoscope", {}) or {}

KARYOSCOPE_CONTAINER = str(_KS_CONFIG.get("container", "") or "")
KARYOSCOPE_DB_ID = str(_KS_CONFIG.get("database", "HKS_human_CHM13_v2"))
KARYOSCOPE_DB_SHA256 = str(_KS_CONFIG.get("database_sha256", "") or "")
KARYOSCOPE_DB_URL = str(_KS_CONFIG.get("database_url", "") or "")
KARYOSCOPE_KEEP_READ_ANNOTATIONS = bool(_KS_CONFIG.get("keep_read_annotations", True))
KARYOSCOPE_MALE_Y_PPM = float(_KS_CONFIG.get("male_y_ppm", 1000))
KARYOSCOPE_FEMALE_Y_PPM = float(_KS_CONFIG.get("female_y_ppm", 100))
KARYOSCOPE_MAX_DEVIATION = float(_KS_CONFIG.get("max_deviation", 0.2))
KARYOSCOPE_DB_ROOT = DIR_LOCAL_REF.joinpath("karyoscope")


# container: a local .sif, or a registry URI (oras://, docker://, library://)
# that Snakemake pulls itself on a server with internet
if not KARYOSCOPE_CONTAINER:
    err_msg = "Error: KaryoScope selected, but no 'karyoscope: container:' is configured."
    logerr(err_msg)
    raise ValueError(err_msg)

if "://" not in KARYOSCOPE_CONTAINER and not pathlib.Path(KARYOSCOPE_CONTAINER).is_file():
    err_msg = f"Configured karyoscope container is not accessible: {KARYOSCOPE_CONTAINER}"
    logerr(err_msg)
    raise FileNotFoundError(err_msg)


# feature sets: defaults plus whatever 'karyo-features' adds (parameter file
# or --config karyo-features=region,repeat)
_KS_EXTRA_FEATURES = [
    fs.strip() for fs in str(config.get("karyo-features", "") or "").split(",") if fs.strip()
]
_KS_UNKNOWN_FEATURES = sorted(set(_KS_EXTRA_FEATURES) - set(KARYOSCOPE_FEATURE_SETS_ALL))
if _KS_UNKNOWN_FEATURES:
    err_msg = (
        f"Error: unknown karyo-features {_KS_UNKNOWN_FEATURES}. "
        f"Valid: {', '.join(KARYOSCOPE_FEATURE_SETS_ALL)}"
    )
    logerr(err_msg)
    raise ValueError(err_msg)

KARYOSCOPE_FEATURE_SETS = [
    fs for fs in KARYOSCOPE_FEATURE_SETS_ALL
    if fs in KARYOSCOPE_FEATURE_SETS_DEFAULT or fs in _KS_EXTRA_FEATURES
]
logout(f"KaryoScope feature sets: {','.join(KARYOSCOPE_FEATURE_SETS)}")


# samples: FASTQ input only (CRAM would need --reference, not supported yet)
SAMPLES_KARYOSCOPE = [
    sample for sample in SAMPLES
    if classify_sample_input_type(sample, SAMPLE_INPUT_FILES[sample]) not in (None, "cram")
]

if not SAMPLES_KARYOSCOPE:
    err_msg = "Error: no samples are compatible with KaryoScope annotation (need FASTQ input)."
    logerr(err_msg)
    raise ValueError(err_msg)


def karyoscope_maybe_temp(path):
    """Mark the per-read annotations temp() unless they should be kept."""
    return path if KARYOSCOPE_KEEP_READ_ANNOTATIONS else temp(path)


# database

localrules: prepare_karyoscope_database


rule prepare_karyoscope_database:
    """
    Make sure the KaryoScope database is installed and registered in
    local_ref/karyoscope: already registered -> done; extracted folder ->
    register; tarball -> verify, extract, register; nothing -> download;
    download fails -> error with instructions for a manual download.
    Local rule, so a download (if possible at all) runs where Snakemake runs.
    """
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
        sha256 = KARYOSCOPE_DB_SHA256,
        url = KARYOSCOPE_DB_URL
    shell:
        "bash {params.script} '{params.db_root}' '{params.db_id}' '{params.sha256}'"
            " '{params.url}' '{output.ready}' 2>&1 | tee {log}"


# per-sample annotation and summary

rule run_karyoscope_annotate:
    """
    'karyoscope annotate' on all FASTQ files of a sample in one call (the
    database index is loaded once per feature set). Writes one smoothed BED
    per input file and feature set: read rank, k-mer offsets within the read,
    label.
    """
    input:
        reads = lambda wildcards: SAMPLE_INPUT_FILES[wildcards.sample],
        # ancient(): re-touching the marker (e.g. after moving the project)
        # must not make finished annotations look outdated
        db_ready = ancient(rules.prepare_karyoscope_database.output.ready)
    output:
        annot_dir = karyoscope_maybe_temp(directory(
            DIR_PROC.joinpath("40-karyotyping", "10_karyoscope", "ks_annot", "{sample}")
        ))
    log:
        DIR_LOG.joinpath("40-karyotyping", "10_karyoscope", "ks_annot", "{sample}.annotate.log")
    benchmark:
        DIR_RSRC.joinpath("40-karyotyping", "10_karyoscope", "ks_annot", "{sample}.annotate.rsrc")
    container:
        KARYOSCOPE_CONTAINER
    threads: CPU_MEDIUM
    resources:
        mem_mb=lambda wildcards, attempt: (24 * 1024) * attempt,
        time_hrs=lambda wildcards, attempt: 6 * attempt
    params:
        inputs = lambda wildcards, input: " ".join(f"-i {f}" for f in input.reads),
        feature_sets = " ".join(f"--feature-set {fs}" for fs in KARYOSCOPE_FEATURE_SETS),
        db_root = KARYOSCOPE_DB_ROOT,
        db_id = KARYOSCOPE_DB_ID
    shell:
        "mkdir -p {output.annot_dir} && "
        "karyoscope annotate {params.inputs} -o {output.annot_dir}"
            " --db {params.db_id} --db-root {params.db_root} {params.feature_sets}"
            " --no-keep-presmoothed --no-preserve-order"
            " --threads {threads} &> {log}"


rule summarize_karyoscope_sample:
    """Sum the annotated k-mer bp per label and feature set for one sample."""
    input:
        annot_dir = rules.run_karyoscope_annotate.output.annot_dir
    output:
        table = DIR_PROC.joinpath(
            "40-karyotyping", "10_karyoscope", "ks_sum", "{sample}.composition.tsv"
        )
    log:
        DIR_LOG.joinpath("40-karyotyping", "10_karyoscope", "ks_sum", "{sample}.summarize.log")
    benchmark:
        DIR_RSRC.joinpath("40-karyotyping", "10_karyoscope", "ks_sum", "{sample}.summarize.rsrc")
    container:
        KARYOSCOPE_CONTAINER
    threads: CPU_LOW
    resources:
        mem_mb=lambda wildcards, attempt: 2048 * attempt,
        time_hrs=lambda wildcards, attempt: 2 * attempt
    params:
        script = get_script("karyoscope_summarize.py"),
        db_id = KARYOSCOPE_DB_ID,
        feature_sets = ",".join(KARYOSCOPE_FEATURE_SETS)
    shell:
        "python3 {params.script} sample --sample {wildcards.sample}"
            " --annot-dir {input.annot_dir} --database {params.db_id}"
            " --feature-sets {params.feature_sets} --threads {threads}"
            " --output {output.table} &> {log}"


# cohort tables

rule merge_karyoscope_cohort:
    """
    Merge the per-sample tables into one composition table per feature set
    (fraction per label) and a chromosome dosage table (autosomes relative to
    the cohort median, X/Y relative to the autosomes, inferred sex, flags).
    """
    input:
        tables = expand(rules.summarize_karyoscope_sample.output.table, sample=SAMPLES_KARYOSCOPE)
    output:
        composition = expand(
            DIR_RES.joinpath("karyotyping", "karyoscope", "SAMPLES.{feature_set}.composition.tsv"),
            feature_set=KARYOSCOPE_FEATURE_SETS
        ),
        dosage = DIR_RES.joinpath("karyotyping", "karyoscope", "SAMPLES.chromosome_dosage.tsv")
    log:
        DIR_LOG.joinpath("40-karyotyping", "10_karyoscope", "ks_cohort", "SAMPLES.merge.log")
    container:
        KARYOSCOPE_CONTAINER
    threads: CPU_LOW
    resources:
        mem_mb=lambda wildcards, attempt: 2048 * attempt,
        time_hrs=lambda wildcards, attempt: 1 * attempt
    params:
        script = get_script("karyoscope_summarize.py"),
        outdir = lambda wildcards, output: pathlib.Path(output.dosage).parent,
        feature_sets = ",".join(KARYOSCOPE_FEATURE_SETS),
        male_y_ppm = KARYOSCOPE_MALE_Y_PPM,
        female_y_ppm = KARYOSCOPE_FEMALE_Y_PPM,
        max_deviation = KARYOSCOPE_MAX_DEVIATION
    shell:
        "python3 {params.script} cohort --inputs {input.tables}"
            " --feature-sets {params.feature_sets} --outdir {params.outdir}"
            " --male-y-ppm {params.male_y_ppm} --female-y-ppm {params.female_y_ppm}"
            " --max-deviation {params.max_deviation} &> {log}"


rule run_all_karyoscope_annotation:
    input:
        summary = [
            *rules.merge_karyoscope_cohort.output.composition,
            rules.merge_karyoscope_cohort.output.dosage,
        ]
