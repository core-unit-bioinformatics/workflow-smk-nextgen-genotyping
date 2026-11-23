import pathlib
import re

import yaml


_KS_CONFIG = config.get("karyoscope", {}) or {}


def karyoscope_list(value):
    """Turn a comma-separated string or a YAML list from the config into a list."""
    if value is None:
        return []
    items = value if isinstance(value, list) else str(value).split(",")
    return [str(item).strip() for item in items if str(item).strip()]


KARYOSCOPE_CONTAINER = str(_KS_CONFIG.get("container", "") or "")
KARYOSCOPE_DB_ID = str(_KS_CONFIG.get("database", "HKS_CHM13v2_karyo"))
KARYOSCOPE_DB_SHA256 = str(_KS_CONFIG.get("database_sha256", "") or "")
KARYOSCOPE_BIN_SIZE_MB = int(_KS_CONFIG.get("bin_size_mb", 1))
KARYOSCOPE_KEEP_READ_ANNOTATIONS = bool(_KS_CONFIG.get("keep_read_annotations", True))
KARYOSCOPE_REFERENCE_SAMPLES = karyoscope_list(_KS_CONFIG.get("reference_samples"))
KARYOSCOPE_MALE_Y_PPM = float(_KS_CONFIG.get("male_y_ppm", 1000))
KARYOSCOPE_FEMALE_Y_PPM = float(_KS_CONFIG.get("female_y_ppm", 500))
KARYOSCOPE_X_DIPLOID_PPM = float(_KS_CONFIG.get("x_diploid_ppm", 53000))
KARYOSCOPE_X_COPY_TOLERANCE = float(_KS_CONFIG.get("x_copy_tolerance", 0.25))
KARYOSCOPE_Y_HAPLOID_PPM = float(_KS_CONFIG.get("y_haploid_ppm", 3500))
KARYOSCOPE_MAX_DEVIATION = float(_KS_CONFIG.get("max_deviation", 0.2))

KARYOSCOPE_DB_ROOT = DIR_LOCAL_REF.joinpath("karyoscope")
KARYOSCOPE_SOURCES_DIR = KARYOSCOPE_DB_ROOT.joinpath("sources")
KARYOSCOPE_DB_READY = KARYOSCOPE_DB_ROOT.joinpath(f"{KARYOSCOPE_DB_ID}.ready")
KARYOSCOPE_RESULTS_DIR = DIR_RES.joinpath("karyotyping", "karyoscope")

# feature sets the summary needs for its dosage tables
KARYOSCOPE_BINS_SET = f"bins_{KARYOSCOPE_BIN_SIZE_MB}mb"
KARYOSCOPE_FEATURE_SETS_DEFAULT = ["chromosome", "gene", "cytoband", KARYOSCOPE_BINS_SET]
# feature sets of a database built by this workflow (build_karyoscope_database)
KARYOSCOPE_BUILD_SETS = ["chromosome", "region", "gene", "cytoband", KARYOSCOPE_BINS_SET]

# source files for building the database: name -> (url, sha256 or "")
KARYOSCOPE_SOURCES = {
    # T2T-CHM13v2.0 genome (analysis set, ~0.9 GB): the complete, gap-free human
    # reference sequence chr1-22, X, Y (HG002 Y), chrM. All k-mers of the
    # database come from it; chrM is excluded from every feature set.
    "chm13v2.0.fa.gz": (
        "https://s3-us-west-2.amazonaws.com/human-pangenomics/T2T/CHM13/assemblies/analysis_set/chm13v2.0.fa.gz",  # noqa: E501
        "",  # the build checks the sequence content instead
    ),
    # Centromeric satellite annotation of CHM13 (CenSat v2.1, BED): positions of
    # alpha-satellite arrays (hor, mon), HSat1-3, beta/gamma satellites, rDNA and
    # the centromere transition zones (ct). Source of the 'region' feature set,
    # which also derives p_arm / q_arm from the centromere position.
    "chm13v2.0.cenSatv2.1.bed": (
        "https://raw.githubusercontent.com/hloucks/CenSatData/refs/heads/main/CHM13/chm13v2.0.cenSatv2.1.bed",  # noqa: E501
        "c6f35d83e4b28f33807c2f65df76b78444f246aa9fb82a3c262bde35e6a6a78c",
    ),
    # NCBI RefSeq gene annotation of CHM13 (GTF): genes, transcripts and exons,
    # with RefSeq sequence names (NC_060925.1 = chr1, ...). Source of the 'gene'
    # feature set (exon / intron / intergenic).
    "CHM13.gtf.gz": (
        "https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/009/914/755/GCF_009914755.1_T2T-CHM13v2.0/GCF_009914755.1_T2T-CHM13v2.0_genomic.gtf.gz",  # noqa: E501
        # NCBI updates this file in place; checksum of the version current in
        # Nov 2026 (MD5 b8d2cf659c44bf3773e9dcaa875ac4a1 as in NCBI's md5checksums.txt)
        "a72e1bc4a219b35cdde0f56c3a1333c4137e72e751390dfe30e2046ef115863e",
    ),
    # Cytogenetic bands of CHM13 from the T2T consortium (BED: chrom, start, end,
    # band name such as p36.33, Giemsa stain): the light/dark band pattern seen
    # under the microscope, with positions on CHM13. Source of the 'cytoband'
    # feature set; the arms (p/q) come from the band names.
    "chm13v2.0_cytobands_allchrs.bed": (
        "https://s3-us-west-2.amazonaws.com/human-pangenomics/T2T/CHM13/assemblies/annotation/chm13v2.0_cytobands_allchrs.bed",  # noqa: E501
        "",
    ),
}


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


# database state at startup: decides whether the database is built or only
# registered
def karyoscope_db_state():
    """Return 'registered', 'present', 'tarball' or 'build' for the configured database."""  # noqa: E501
    installed = KARYOSCOPE_DB_ROOT.joinpath("installed.json")
    if installed.is_file():
        databases = json.loads(installed.read_text(encoding="utf-8")).get("databases", {})
        if KARYOSCOPE_DB_ID in databases:
            return "registered"
    if KARYOSCOPE_DB_ROOT.joinpath(KARYOSCOPE_DB_ID, "manifest.yaml").is_file():
        return "present"
    if KARYOSCOPE_DB_ROOT.joinpath(f"{KARYOSCOPE_DB_ID}.tar.gz").is_file():
        return "tarball"
    return "build"


def karyoscope_available_sets(state):
    """Feature sets the database has (or will have), None if unknown before extraction."""  # noqa: E501
    if state == "build":
        return KARYOSCOPE_BUILD_SETS
    manifest = KARYOSCOPE_DB_ROOT.joinpath(KARYOSCOPE_DB_ID, "manifest.yaml")
    if manifest.is_file():
        return yaml.safe_load(manifest.read_text(encoding="utf-8")).get("feature_sets", [])
    return None


KARYOSCOPE_DB_STATE = karyoscope_db_state()
logout(f"KaryoScope database {KARYOSCOPE_DB_ID}: {KARYOSCOPE_DB_STATE}")


# feature sets: defaults (karyoscope.default_features, or the built-in list)
# plus whatever 'karyo-features' adds (parameter file or
# --config karyo-features=region)
_KS_DEFAULT_FEATURES = (
    karyoscope_list(_KS_CONFIG["default_features"])
    if "default_features" in _KS_CONFIG
    else KARYOSCOPE_FEATURE_SETS_DEFAULT
)
_KS_EXTRA_FEATURES = karyoscope_list(config.get("karyo-features"))
KARYOSCOPE_FEATURE_SETS = list(dict.fromkeys(_KS_DEFAULT_FEATURES + _KS_EXTRA_FEATURES))
if not KARYOSCOPE_FEATURE_SETS:
    err_msg = "Error: no KaryoScope feature sets selected."
    logerr(err_msg)
    raise ValueError(err_msg)

_KS_AVAILABLE_SETS = karyoscope_available_sets(KARYOSCOPE_DB_STATE)
if _KS_AVAILABLE_SETS is not None:
    _KS_MISSING_SETS = [fs for fs in KARYOSCOPE_FEATURE_SETS if fs not in _KS_AVAILABLE_SETS]
    if _KS_MISSING_SETS:
        err_msg = (
            f"Error: feature set(s) {_KS_MISSING_SETS} are not in the KaryoScope database "
            f"{KARYOSCOPE_DB_ID}. Available: {', '.join(_KS_AVAILABLE_SETS)}"
        )
        logerr(err_msg)
        raise ValueError(err_msg)
logout(f"KaryoScope feature sets: {','.join(KARYOSCOPE_FEATURE_SETS)}")

# warn about summary tables that cannot be produced with these feature sets
if "chromosome" not in KARYOSCOPE_FEATURE_SETS:
    logout("WARNING: KaryoScope 'chromosome' not annotated: no chromosome dosage / sex call")
if "cytoband" not in KARYOSCOPE_FEATURE_SETS:
    logout("WARNING: KaryoScope 'cytoband' not annotated: no arm and band dosage")
KARYOSCOPE_BINS_SETS = [fs for fs in KARYOSCOPE_FEATURE_SETS if fs.startswith("bins_")]
if not KARYOSCOPE_BINS_SETS:
    logout("WARNING: no KaryoScope 'bins_*' set annotated: no bin dosage")


# cohort tables the summary writes for these feature sets
KARYOSCOPE_COHORT_TABLES = [
    KARYOSCOPE_RESULTS_DIR.joinpath(f"SAMPLES.{fs}.composition.tsv")
    for fs in KARYOSCOPE_FEATURE_SETS
    if fs != "cytoband" and not fs.startswith("bins_")
]
if "chromosome" in KARYOSCOPE_FEATURE_SETS:
    KARYOSCOPE_COHORT_TABLES.append(KARYOSCOPE_RESULTS_DIR.joinpath("SAMPLES.chromosome_dosage.tsv"))
if "cytoband" in KARYOSCOPE_FEATURE_SETS:
    KARYOSCOPE_COHORT_TABLES.append(KARYOSCOPE_RESULTS_DIR.joinpath("SAMPLES.arm_dosage.tsv"))
    KARYOSCOPE_COHORT_TABLES.append(KARYOSCOPE_RESULTS_DIR.joinpath("SAMPLES.cytoband_dosage.tsv"))
for _ks_bins_set in KARYOSCOPE_BINS_SETS:
    KARYOSCOPE_COHORT_TABLES.append(
        KARYOSCOPE_RESULTS_DIR.joinpath(f"SAMPLES.{_ks_bins_set}_dosage.tsv")
    )


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

if KARYOSCOPE_DB_STATE == "build":

    localrules: fetch_karyoscope_source


    rule fetch_karyoscope_source:
        """
        Download one source file for the database build into
        local_ref/karyoscope/sources. Local rule (runs where Snakemake runs);
        without internet it stops with instructions for a manual download.
        A file that is already there is not downloaded again.
        """
        output:
            source = KARYOSCOPE_SOURCES_DIR.joinpath("{source}")
        wildcard_constraints:
            source = "|".join(re.escape(name) for name in KARYOSCOPE_SOURCES)
        log:
            DIR_LOG.joinpath("40-karyotyping", "10_karyoscope", "ks_db", "fetch.{source}.log")
        params:
            script = get_script("karyoscope_fetch_source.sh", extension="sh"),
            url = lambda wildcards: KARYOSCOPE_SOURCES[wildcards.source][0],
            sha256 = lambda wildcards: KARYOSCOPE_SOURCES[wildcards.source][1]
        shell:
            "bash {params.script} '{output.source}' '{params.url}' '{params.sha256}'"
                " 2>&1 | tee {log}"


    rule build_karyoscope_database:
        """
        Build and register the workflow's KaryoScope database (chromosome,
        region, gene, cytoband with arm level, fixed-size bins) from the
        T2T-CHM13v2.0 sources. Memory-hungry (~80 GB peak at k=31).
        """
        input:
            sources = expand(KARYOSCOPE_SOURCES_DIR.joinpath("{source}"), source=KARYOSCOPE_SOURCES)
        output:
            ready = KARYOSCOPE_DB_READY
        log:
            DIR_LOG.joinpath("40-karyotyping", "10_karyoscope", "ks_db", f"{KARYOSCOPE_DB_ID}.build.log")
        benchmark:
            DIR_RSRC.joinpath("40-karyotyping", "10_karyoscope", "ks_db", f"{KARYOSCOPE_DB_ID}.build.rsrc")
        container:
            KARYOSCOPE_CONTAINER
        threads: 16
        resources:
            # ~80 GB peak at k=31 (KaryoScope's own CHM13 measurement)
            mem_mb=lambda wildcards, attempt: (128 * 1024) * attempt,
            time_hrs=lambda wildcards, attempt: 4 * attempt
        params:
            script = get_script("karyoscope_build_db.sh", extension="sh"),
            feature_beds = get_script("karyoscope_feature_beds.py"),
            sources_dir = KARYOSCOPE_SOURCES_DIR,
            db_root = KARYOSCOPE_DB_ROOT,
            db_id = KARYOSCOPE_DB_ID,
            bin_size_mb = KARYOSCOPE_BIN_SIZE_MB,
            # HKS memory budget (GB) during the build
            mem_gigas = 32
        shell:
            "bash {params.script} '{params.sources_dir}' '{params.db_root}' '{params.db_id}'"
                " {params.bin_size_mb} {threads} {params.mem_gigas} '{params.feature_beds}'"
                " '{output.ready}' &> {log}"

else:

    localrules: prepare_karyoscope_database


    rule prepare_karyoscope_database:
        """
        Register a KaryoScope database that is already in local_ref/karyoscope
        (folder or tarball) and check that it has the selected feature sets.
        """
        output:
            ready = KARYOSCOPE_DB_READY
        log:
            DIR_LOG.joinpath("40-karyotyping", "10_karyoscope", "ks_db", f"{KARYOSCOPE_DB_ID}.db.log")
        container:
            KARYOSCOPE_CONTAINER
        params:
            script = get_script("karyoscope_db.sh", extension="sh"),
            db_root = KARYOSCOPE_DB_ROOT,
            db_id = KARYOSCOPE_DB_ID,
            sha256 = KARYOSCOPE_DB_SHA256,
            feature_sets = ",".join(KARYOSCOPE_FEATURE_SETS)
        shell:
            "bash {params.script} '{params.db_root}' '{params.db_id}' '{params.sha256}'"
                " '{params.feature_sets}' '{output.ready}' 2>&1 | tee {log}"


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
        db_ready = ancient(KARYOSCOPE_DB_READY)
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
        time_hrs=lambda wildcards, attempt: 24 * attempt
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
        time_hrs=lambda wildcards, attempt: 12 * attempt
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
    Merge the per-sample tables into the cohort tables: one composition table
    per feature set (not for cytoband/bins), chromosome dosage and sex call
    (needs 'chromosome'), arm and band dosage (needs 'cytoband'), bin dosage
    (needs a 'bins_*' set). Ratios are relative to the median of the reference
    samples (karyoscope.reference_samples, default: all samples).
    """
    input:
        tables = expand(rules.summarize_karyoscope_sample.output.table, sample=SAMPLES_KARYOSCOPE)
    output:
        tables = KARYOSCOPE_COHORT_TABLES
    log:
        DIR_LOG.joinpath("40-karyotyping", "10_karyoscope", "ks_cohort", "SAMPLES.merge.log")
    container:
        KARYOSCOPE_CONTAINER
    threads: CPU_LOW
    resources:
        mem_mb=lambda wildcards, attempt: 8192 * attempt,
        time_hrs=lambda wildcards, attempt: 1 * attempt
    params:
        script = get_script("karyoscope_summarize.py"),
        outdir = KARYOSCOPE_RESULTS_DIR,
        feature_sets = ",".join(KARYOSCOPE_FEATURE_SETS),
        reference_samples = ",".join(KARYOSCOPE_REFERENCE_SAMPLES),
        male_y_ppm = KARYOSCOPE_MALE_Y_PPM,
        female_y_ppm = KARYOSCOPE_FEMALE_Y_PPM,
        max_deviation = KARYOSCOPE_MAX_DEVIATION,
        x_diploid_ppm = KARYOSCOPE_X_DIPLOID_PPM,
        x_copy_tolerance = KARYOSCOPE_X_COPY_TOLERANCE,
        y_haploid_ppm = KARYOSCOPE_Y_HAPLOID_PPM
    shell:
        "python3 {params.script} cohort --inputs {input.tables}"
            " --feature-sets {params.feature_sets} --outdir {params.outdir}"
            " --reference-samples '{params.reference_samples}'"
            " --male-y-ppm {params.male_y_ppm} --female-y-ppm {params.female_y_ppm}"
            " --max-deviation {params.max_deviation}"
            " --x-diploid-ppm {params.x_diploid_ppm}"
            " --x-copy-tolerance {params.x_copy_tolerance}"
            " --y-haploid-ppm {params.y_haploid_ppm} &> {log}"


rule run_all_karyoscope_annotation:
    input:
        summary = KARYOSCOPE_COHORT_TABLES
