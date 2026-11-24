#!/usr/bin/env python3
"""Condense KaryoScope per-read annotations into per-sample and cohort tables.

Subcommands:
  sample  sum the annotated k-mer bp per label and feature set for one sample
  cohort  merge the per-sample tables into cohort tables:
            SAMPLES.<set>.composition.tsv   per set, fraction per label
            SAMPLES.reference_values.tsv    expected share per label (the baseline)
            SAMPLES.chromosome_dosage.tsv   needs 'chromosome': copies, sex call
            SAMPLES.arm_dosage.tsv          needs 'cytoband': copies per arm
            SAMPLES.cytoband_dosage.tsv     needs 'cytoband': copies per band
            SAMPLES.<bins>_dosage.tsv       needs a 'bins_*' set: copies per bin
          Tables whose feature set was not annotated are skipped with a warning.

Copies = expected copies x (sample share / expected share), where a share is the
label's bp divided by the autosomal bp of the same feature set, and the expected
share comes from normal reference genomes (reference values file, or reference
samples of the run): autosomes 2 copies, chrX 2 (from females), chrY 1 (males).
"""

import argparse
import collections
import csv
import pathlib
import re
import statistics
import subprocess
import sys

AUTOSOMES = [f"chr{i}" for i in range(1, 23)]
CHR_X = "chrX"
CHR_Y = "chrY"
CHROMOSOMES = [*AUTOSOMES, CHR_X, CHR_Y]
NOVEL = "novel"

CHROMOSOME_SET = "chromosome"
CYTOBAND_SET = "cytoband"
BINS_PREFIX = "bins_"
ARM_TABLE = "arm"

# Sex call. With reference values: X copies rounded to a whole number (at most
# X_COPY_TOLERANCE off), Y present from Y_PRESENT_COPIES, absent up to
# Y_ABSENT_COPIES, in between ambiguous (e.g. mosaic loss of Y).
X_COPY_TOLERANCE = 0.25
Y_PRESENT_COPIES = 0.5
Y_ABSENT_COPIES = 0.1
# Rough values (ppm of autosomal bp, chromosome set of HKS_CHM13v2_karyo) for a
# first sex call before reference values exist: only used to sort reference
# samples into females (chrX values) and males (chrY values), and as fallback
# when the reference has no female or no male.
BOOTSTRAP_X_DIPLOID_PPM = 53000.0
BOOTSTRAP_Y_PRESENT_PPM = 1000.0
BOOTSTRAP_Y_ABSENT_PPM = 500.0
ARMS = [f"{c.removeprefix('chr')}{arm}" for c in CHROMOSOMES for arm in "pq"]

# cytoband labels: chromosome node "1", arm node "1p", band group "1p36",
# band "1p36.33" (chromosome without the "chr" prefix)
CYTOBAND_RE = re.compile(r"^(\d+|X|Y)(?:([pq])([\d.]*))?$")
# bin labels: chr1_0_1000000
BIN_RE = re.compile(r"^(chr(?:\d+|X|Y))_(\d+)_(\d+)$")

# Output order of the labels per feature set (hierarchy of the CHM13 database).
# Labels not listed here follow alphabetically; "none" (chrM) and "novel" last.
LABEL_ORDER = {
    CHROMOSOME_SET: [
        "categorized",
        "autosome", "metacentric", "submetacentric", "acrocentric",
        *AUTOSOMES,
        "sex", CHR_X, CHR_Y,
    ],
    "gene": ["exon", "intron", "intergenic"],
}  # fmt: skip
TAIL_LABELS = ["none", NOVEL]


def parse_args():
    """Parse the command line."""
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    smp = sub.add_parser("sample", help="summarize one sample")
    smp.add_argument("--sample", required=True, help="sample name")
    smp.add_argument("--annot-dir", required=True, type=pathlib.Path)
    smp.add_argument("--database", required=True, help="KaryoScope database id")
    smp.add_argument("--feature-sets", required=True, help="comma-separated")
    smp.add_argument("--threads", type=int, default=1)
    smp.add_argument("--output", required=True, type=pathlib.Path)

    coh = sub.add_parser("cohort", help="merge per-sample tables")
    coh.add_argument("--inputs", required=True, nargs="+", type=pathlib.Path)
    coh.add_argument("--feature-sets", required=True, help="comma-separated")
    coh.add_argument("--outdir", required=True, type=pathlib.Path)
    coh.add_argument("--database", required=True, help="KaryoScope database id")
    coh.add_argument(
        "--reference-values",
        type=pathlib.Path,
        help="reference values file (SAMPLES.reference_values.tsv of a reference run)",
    )
    coh.add_argument(
        "--reference-samples",
        default="",
        help="comma-separated normal samples of this run to use as reference "
        "(overrides --reference-values)",
    )
    coh.add_argument(
        "--max-deviation",
        type=float,
        default=0.2,
        help="flag copies that deviate from the expected copies by more than this "
        "fraction",
    )
    return parser.parse_args()


def warn(message):
    """Print a warning to stderr (ends up in the rule's log)."""
    print(f"[summarize] WARNING: {message}", file=sys.stderr)


def split_sets(text):
    """Split a comma-separated feature-set list."""
    return [fs for fs in text.split(",") if fs]


def is_bins_set(feature_set):
    """Return True for a fixed-size bin feature set (bins_1mb, ...)."""
    return feature_set.startswith(BINS_PREFIX)


def has_long_dosage(feature_set):
    """Return True for sets reported as long dosage tables instead of compositions."""
    return feature_set == CYTOBAND_SET or is_bins_set(feature_set)


def chrom_rank(chrom):
    """Sort key for a chromosome name with or without the 'chr' prefix."""
    name = chrom.removeprefix("chr")
    if name.isdigit():
        return int(name)
    return {"X": 23, "Y": 24}.get(name, 99)


def parse_cytoband(label):
    """Return (chrom, arm, band) of a cytoband label, or None for other labels."""
    match = CYTOBAND_RE.match(label)
    if not match:
        return None
    chrom, arm, band = match.groups()
    return f"chr{chrom}", arm or "", band or ""


def parse_bin(label):
    """Return (chrom, start, end) of a bin label, or None for other labels."""
    match = BIN_RE.match(label)
    if not match:
        return None
    return match.group(1), int(match.group(2)), int(match.group(3))


def bins_chrom(label):
    """Chromosome of a bin label or of a chromosome node (chr1) in a bins set."""
    parsed = parse_bin(label)
    return parsed[0] if parsed else label


def cytoband_key(label):
    """Genomic sort key: p arm from telomere to centromere, then q arm outwards."""
    chrom, arm, band = parse_cytoband(label)
    number = float(band.rstrip(".")) if band else 0.0
    if arm == "p":
        return (chrom_rank(chrom), 1, -number)
    if arm == "q":
        return (chrom_rank(chrom), 2, number)
    return (chrom_rank(chrom), 0, 0.0)


def bin_key(label):
    """Genomic sort key of a bin label."""
    chrom, start, _end = parse_bin(label)
    return (chrom_rank(chrom), start)


def order_labels(feature_set, labels):
    """Sort labels hierarchically or genomically per feature set."""
    labels = set(labels)
    tail = [lb for lb in TAIL_LABELS if lb in labels]
    if feature_set == CYTOBAND_SET:
        known = sorted((lb for lb in labels if parse_cytoband(lb)), key=cytoband_key)
    elif is_bins_set(feature_set):
        known = sorted((lb for lb in labels if parse_bin(lb)), key=bin_key)
    else:
        known = [lb for lb in LABEL_ORDER.get(feature_set, []) if lb in labels]
    rest = sorted(labels - set(known) - set(tail))
    return known + rest + tail


def count_labels(bed_path, threads):
    """Sum interval lengths (end - start) per label of one bgzipped BED."""
    counts = collections.Counter()
    cmd = ["bgzip", "-dc", "-@", str(threads), str(bed_path)]
    with subprocess.Popen(
        cmd, stdout=subprocess.PIPE, text=True, encoding="utf-8"
    ) as proc:
        for line in proc.stdout:
            if line.startswith(("#", "track", "browser")):
                continue
            fields = line.rstrip("\n").split("\t", 4)
            counts[fields[3]] += int(fields[2]) - int(fields[1])
    if proc.returncode != 0:
        raise RuntimeError(f"bgzip failed on {bed_path} (exit {proc.returncode})")
    return counts


def summarize_sample(args):
    """Write one long table (sample, feature_set, label, bp, fraction)."""
    rows = []
    for feature_set in split_sets(args.feature_sets):
        pattern = f"*.{args.database}.{feature_set}.smoothed.bed.gz"
        bed_files = sorted(args.annot_dir.glob(pattern))
        if not bed_files:
            raise FileNotFoundError(f"no {pattern} in {args.annot_dir}")
        counts = collections.Counter()
        for bed_file in bed_files:
            print(f"[summarize] {bed_file.name}", file=sys.stderr)
            counts.update(count_labels(bed_file, args.threads))
        total = sum(counts.values())
        for label in order_labels(feature_set, counts):
            bp = counts[label]
            fraction = bp / total if total else 0.0
            rows.append([args.sample, feature_set, label, bp, f"{fraction:.8f}"])

    args.output.parent.mkdir(parents=True, exist_ok=True)
    write_tsv(args.output, ["sample", "feature_set", "label", "bp", "fraction"], rows)


def read_sample_tables(paths):
    """Return {sample: {feature_set: {label: bp}}} from per-sample tables."""
    data = {}
    for path in paths:
        with open(path, encoding="utf-8", newline="") as handle:
            for row in csv.DictReader(handle, delimiter="\t"):
                per_set = data.setdefault(row["sample"], {})
                labels = per_set.setdefault(row["feature_set"], {})
                labels[row["label"]] = int(row["bp"])
    return data


def write_tsv(path, header, rows):
    """Write a tab-separated table."""
    with open(path, "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)


# reference values: the expected share of every label for a normal genome


def fmt(value, digits=4):
    """Format a float for the output tables, NA for None."""
    return "NA" if value is None else f"{value:.{digits}f}"


def label_chrom(table, label):
    """Chromosome (chr1 ... chrY) of a label in one of the dosage tables, or None."""
    if table == CHROMOSOME_SET:
        return label if label in CHROMOSOMES else None
    if table in (ARM_TABLE, CYTOBAND_SET):
        parsed = parse_cytoband(label)
        return parsed[0] if parsed else None
    if is_bins_set(table):
        parsed = parse_bin(label)
        return parsed[0] if parsed else None
    return None


def sample_shares(per_set, feature_sets):
    """Return {table: {label: share of the set's autosomal bp}} for one sample."""
    shares = {}
    if CHROMOSOME_SET in feature_sets:
        counts = per_set.get(CHROMOSOME_SET, {})
        autosomal = sum(counts.get(c, 0) for c in AUTOSOMES)
        if autosomal:
            shares[CHROMOSOME_SET] = {
                c: counts.get(c, 0) / autosomal for c in CHROMOSOMES
            }
    if CYTOBAND_SET in feature_sets:
        counts = per_set.get(CYTOBAND_SET, {})
        bands, arms = {}, collections.Counter()
        autosomal = 0
        for label, bp in counts.items():
            parsed = parse_cytoband(label)
            if parsed is None:
                continue
            chrom, arm, band = parsed
            if chrom in AUTOSOMES:
                autosomal += bp
            if arm:
                arms[f"{chrom.removeprefix('chr')}{arm}"] += bp
            if band:
                bands[label] = bp
        if autosomal:
            shares[ARM_TABLE] = {a: arms.get(a, 0) / autosomal for a in ARMS}
            shares[CYTOBAND_SET] = {b: bp / autosomal for b, bp in bands.items()}
    for feature_set in feature_sets:
        if not is_bins_set(feature_set):
            continue
        counts = per_set.get(feature_set, {})
        # bins plus the chromosome nodes (k-mers shared between bins of one
        # chromosome) of the autosomes
        autosomal = sum(bp for lb, bp in counts.items() if bins_chrom(lb) in AUTOSOMES)
        if autosomal:
            shares[feature_set] = {
                lb: bp / autosomal for lb, bp in counts.items() if parse_bin(lb)
            }
    return shares


def expectations_from_samples(shares, sexes, reference):
    """Compute the expected share per table and label from normal samples.

    Autosomes from all of them (2 copies), chrX from the females (2 copies),
    chrY from the males (1 copy).
    """
    groups = {
        "autosome": reference,
        CHR_X: [s for s in reference if sexes.get(s) == "female"],
        CHR_Y: [s for s in reference if sexes.get(s) == "male"],
    }
    for name, label in ((CHR_X, "female"), (CHR_Y, "male")):
        if not groups[name]:
            warn(f"no {label} reference sample: no expected values for {name}")
    expected = {}
    tables = {table for s in reference for table in shares[s]}
    for table in tables:
        labels = {lb for s in reference for lb in shares[s].get(table, {})}
        for label in labels:
            chrom = label_chrom(table, label)
            if chrom is None:
                continue
            group = chrom if chrom in (CHR_X, CHR_Y) else "autosome"
            if not groups[group]:
                continue
            values = [shares[s].get(table, {}).get(label, 0.0) for s in groups[group]]
            expected.setdefault(table, {})[label] = (
                statistics.median(values),
                1 if chrom == CHR_Y else 2,
                len(values),
            )
    return expected


def read_expectations(path, database):
    """Read a reference values file; None if it belongs to another database."""
    expected = {}
    file_database = None
    with open(path, encoding="utf-8", newline="") as handle:
        lines = []
        for line in handle:
            if line.startswith("# database:"):
                file_database = line.split(":", 1)[1].strip()
            elif not line.startswith("#"):
                lines.append(line)
    if file_database != database:
        warn(
            f"{path} is for database {file_database!r}, not {database!r}: "
            "ignored, using the samples of this run as reference"
        )
        return None
    for row in csv.DictReader(lines, delimiter="\t"):
        expected.setdefault(row["table"], {})[row["label"]] = (
            float(row["expected_ppm"]) / 1e6,
            int(row["expected_copies"]),
            int(row["n_samples"]),
        )
    return expected


def write_expectations(path, expected, database, source):
    """Write the reference values used in this run (reusable as default file)."""
    rows = []
    for table in sorted(expected):
        for label in sorted(expected[table], key=lambda lb: table_sort_key(table, lb)):
            share, copies, n_samples = expected[table][label]
            chrom = label_chrom(table, label)
            rows.append([table, label, chrom, f"{share * 1e6:.3f}", copies, n_samples])
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(f"# database: {database}\n")
        handle.write(f"# source: {source}\n")
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(
            ["table", "label", "chrom", "expected_ppm", "expected_copies", "n_samples"]
        )
        writer.writerows(rows)


def table_sort_key(table, label):
    """Genomic sort key for a label of any dosage table."""
    if table == CYTOBAND_SET:
        return cytoband_key(label)
    if is_bins_set(table):
        return bin_key(label)
    if table == ARM_TABLE:
        return (ARMS.index(label), 0)
    return (CHROMOSOMES.index(label), 0)


def copies(share, expected):
    """Copy number from a share and its (expected share, expected copies)."""
    if expected is None or expected[0] == 0:
        return None
    return expected[1] * share / expected[0]


def flag(value, expected_copies, max_deviation):
    """Return 'gain', 'loss' or '.' relative to the expected copy number."""
    if value is None or abs(value / expected_copies - 1) <= max_deviation:
        return "."
    return "gain" if value > expected_copies else "loss"


# sex call (chromosome set)


def call_sex_chromosomes(x_copies, y_status):
    """Return (sex_chromosomes, inferred_sex) from X copies and the Y status."""
    x_count = round(x_copies)
    if x_count < 1 or abs(x_copies - x_count) > X_COPY_TOLERANCE:
        x_count = None
    if x_count is None or y_status == "ambiguous":
        return "ambiguous", "ambiguous"
    sex_chromosomes = "X" * x_count + ("Y" if y_status == "present" else "")
    if sex_chromosomes == "X":
        sex_chromosomes = "X0"
    inferred_sex = {"XX": "female", "XY": "male"}.get(sex_chromosomes, "atypical")
    return sex_chromosomes, inferred_sex


def y_status_from(value, present, absent):
    """Return 'present', 'absent' or 'ambiguous' for a Y value and two thresholds."""
    if value >= present:
        return "present"
    if value <= absent:
        return "absent"
    return "ambiguous"


def bootstrap_sexes(shares):
    """Rough sex per sample from fixed ppm values (to pick X/Y reference samples)."""
    sexes = {}
    for sample, per_table in shares.items():
        share = per_table.get(CHROMOSOME_SET)
        if share is None:
            continue
        x_copies = 2 * share[CHR_X] * 1e6 / BOOTSTRAP_X_DIPLOID_PPM
        y_status = y_status_from(
            share[CHR_Y] * 1e6, BOOTSTRAP_Y_PRESENT_PPM, BOOTSTRAP_Y_ABSENT_PPM
        )
        sexes[sample] = call_sex_chromosomes(x_copies, y_status)[1]
    return sexes


def sex_calls(shares, expected):
    """Return {sample: X/Y copies and sex call}, from the reference values."""
    exp = expected.get(CHROMOSOME_SET, {})
    calls = {}
    for sample, per_table in shares.items():
        share = per_table.get(CHROMOSOME_SET)
        if share is None:
            continue
        x_copies = copies(share[CHR_X], exp.get(CHR_X))
        if x_copies is None:
            x_copies = 2 * share[CHR_X] * 1e6 / BOOTSTRAP_X_DIPLOID_PPM
        y_copies = copies(share[CHR_Y], exp.get(CHR_Y))
        if y_copies is None:
            y_status = y_status_from(
                share[CHR_Y] * 1e6, BOOTSTRAP_Y_PRESENT_PPM, BOOTSTRAP_Y_ABSENT_PPM
            )
        else:
            y_status = y_status_from(y_copies, Y_PRESENT_COPIES, Y_ABSENT_COPIES)
        sex_chromosomes, inferred_sex = call_sex_chromosomes(x_copies, y_status)
        calls[sample] = {
            "x_copies": x_copies,
            "y_copies": y_copies,
            "y_status": y_status,
            "sex_chromosomes": sex_chromosomes,
            "inferred_sex": inferred_sex,
        }
    return calls


# dosage tables


def write_chromosome_dosage(data, calls, shares, expected, args, path):
    """Write per-sample copies per chromosome, sex call and flags."""
    exp = expected.get(CHROMOSOME_SET, {})
    header = [
        "sample", "total_bp", "autosomal_bp", "autosomal_fraction", "novel_fraction",
        *(f"{c}_copies" for c in AUTOSOMES), "chrX_copies", "chrY_copies",
        "sex_chromosomes", "inferred_sex", "flags",
    ]  # fmt: skip
    rows = []
    for sample in sorted(calls):
        counts = data[sample].get(CHROMOSOME_SET, {})
        total = sum(counts.values())
        autosomal = sum(counts.get(c, 0) for c in AUTOSOMES)
        share = shares[sample][CHROMOSOME_SET]
        m = calls[sample]
        auto = {c: copies(share[c], exp.get(c)) for c in AUTOSOMES}
        flags = [
            f"{c}:{v:.2f}"
            for c, v in auto.items()
            if flag(v, 2, args.max_deviation) != "."
        ]
        if m["sex_chromosomes"] not in ("XX", "XY"):
            flags.append(
                f"sex:{m['sex_chromosomes']}(chrX_copies={fmt(m['x_copies'], 2)},"
                f"chrY_copies={fmt(m['y_copies'], 2)},y={m['y_status']})"
            )
        rows.append([
            sample, total, autosomal, fmt(autosomal / total, 6),
            fmt(counts.get(NOVEL, 0) / total, 6),
            *(fmt(auto[c], 2) for c in AUTOSOMES),
            fmt(m["x_copies"], 2), fmt(m["y_copies"], 2),
            m["sex_chromosomes"], m["inferred_sex"], ";".join(flags) if flags else ".",
        ])  # fmt: skip
    write_tsv(path, header, rows)


def write_arm_dosage(shares, expected, args, path):
    """Write per-sample copies per arm (X/Y relative to the expected sex) and flags."""
    exp = expected.get(ARM_TABLE, {})
    header = ["sample", *(f"{a}_copies" for a in ARMS), "flags"]
    rows = []
    for sample in sorted(shares):
        share = shares[sample].get(ARM_TABLE, {})
        values = {a: copies(share.get(a, 0.0), exp.get(a)) for a in ARMS}
        flags = [
            f"{a}:{values[a]:.2f}"
            for a in ARMS
            if not a.startswith(("X", "Y"))
            and flag(values[a], 2, args.max_deviation) != "."
        ]
        rows.append([
            sample,
            *(fmt(values[a], 2) for a in ARMS),
            ";".join(flags) if flags else ".",
        ])  # fmt: skip
    write_tsv(path, header, rows)


def write_cytoband_dosage(shares, expected, args, path):
    """Write a long table: one row per sample and band, with copies and flag."""
    exp = expected.get(CYTOBAND_SET, {})
    labels = sorted(
        {lb for s in shares.values() for lb in s.get(CYTOBAND_SET, {})} | set(exp),
        key=cytoband_key,
    )
    rows = []
    for sample in sorted(shares):
        share = shares[sample].get(CYTOBAND_SET, {})
        for label in labels:
            chrom, arm, _band = parse_cytoband(label)
            value = copies(share.get(label, 0.0), exp.get(label))
            mark = flag(value, 2, args.max_deviation) if chrom in AUTOSOMES else "."
            rows.append([
                sample, chrom, f"{chrom.removeprefix('chr')}{arm}", label,
                fmt(value, 2), mark,
            ])  # fmt: skip
    header = ["sample", "chrom", "arm", "band", "copies", "flag"]
    write_tsv(path, header, rows)


def write_bins_dosage(shares, expected, feature_set, args, path):
    """Write a long table: one row per sample and bin, with copies and flag."""
    exp = expected.get(feature_set, {})
    labels = sorted(
        {lb for s in shares.values() for lb in s.get(feature_set, {})} | set(exp),
        key=bin_key,
    )
    rows = []
    for sample in sorted(shares):
        share = shares[sample].get(feature_set, {})
        for label in labels:
            chrom, start, end = parse_bin(label)
            value = copies(share.get(label, 0.0), exp.get(label))
            mark = flag(value, 2, args.max_deviation) if chrom in AUTOSOMES else "."
            rows.append([
                sample, chrom, start, end, fmt(value, 2), mark,
            ])  # fmt: skip
    header = ["sample", "chrom", "start", "end", "copies", "flag"]
    write_tsv(path, header, rows)


def write_composition(data, feature_set, path):
    """Write a wide sample x label table of fractions for one feature set."""
    labels = order_labels(
        feature_set, {label for s in data.values() for label in s.get(feature_set, {})}
    )
    rows = []
    for sample in sorted(data):
        counts = data[sample].get(feature_set, {})
        total = sum(counts.values())
        fractions = [
            f"{counts.get(lb, 0) / total:.8f}" if total else "NA" for lb in labels
        ]
        rows.append([sample, total, *fractions])
    write_tsv(path, ["sample", "total_bp", *labels], rows)


# cohort


def select_reference(data, text):
    """Return the requested reference samples that are in this run."""
    requested = [s for s in text.split(",") if s]
    reference = [s for s in requested if s in data]
    missing = sorted(set(requested) - set(reference))
    if missing:
        warn(f"reference samples not in this run, ignored: {', '.join(missing)}")
    if not reference:
        raise ValueError("none of the --reference-samples are in this run")
    return reference


def resolve_expectations(data, shares, sexes, args):
    """Return the reference values and where they come from.

    In order of preference: the run's --reference-samples, the
    --reference-values file, all samples of the run.
    """
    if args.reference_samples:
        reference = select_reference(data, args.reference_samples)
        source = f"reference samples of this run: {','.join(reference)}"
    else:
        if args.reference_values and args.reference_values.is_file():
            expected = read_expectations(args.reference_values, args.database)
            if expected is not None:
                source = f"reference values file {args.reference_values}"
                print(f"[summarize] baseline: {source}", file=sys.stderr)
                return expected, source
        reference = sorted(data)
        source = f"all samples of this run (no reference given): {','.join(reference)}"
        warn(
            "no reference values file and no reference samples: copies are relative "
            "to the median of this run's samples"
        )
    if len(reference) < 5:
        warn(f"only {len(reference)} reference samples: medians are not robust")
    print(f"[summarize] baseline: {source}", file=sys.stderr)
    return expectations_from_samples(shares, sexes, reference), source


def summarize_cohort(args):
    """Write the composition tables, the reference values and the dosage tables."""
    data = read_sample_tables(args.inputs)
    feature_sets = split_sets(args.feature_sets)
    outdir = args.outdir
    outdir.mkdir(parents=True, exist_ok=True)

    for feature_set in feature_sets:
        if not has_long_dosage(feature_set):
            out = outdir.joinpath(f"SAMPLES.{feature_set}.composition.tsv")
            write_composition(data, feature_set, out)

    shares = {s: sample_shares(per_set, feature_sets) for s, per_set in data.items()}
    sexes = bootstrap_sexes(shares)
    if not sexes:
        warn("'chromosome' not annotated: no sex call, no X/Y reference values")
    expected, source = resolve_expectations(data, shares, sexes, args)
    calls = sex_calls(shares, expected)
    write_expectations(
        outdir.joinpath("SAMPLES.reference_values.tsv"), expected, args.database, source
    )

    if calls:
        out = outdir.joinpath("SAMPLES.chromosome_dosage.tsv")
        write_chromosome_dosage(data, calls, shares, expected, args, out)

    if CYTOBAND_SET in feature_sets:
        write_arm_dosage(
            shares, expected, args, outdir.joinpath("SAMPLES.arm_dosage.tsv")
        )
        out = outdir.joinpath("SAMPLES.cytoband_dosage.tsv")
        write_cytoband_dosage(shares, expected, args, out)
    else:
        warn("'cytoband' not annotated: skipping arm and band dosage")

    bins_sets = [fs for fs in feature_sets if is_bins_set(fs)]
    for feature_set in bins_sets:
        out = outdir.joinpath(f"SAMPLES.{feature_set}_dosage.tsv")
        write_bins_dosage(shares, expected, feature_set, args, out)
    if not bins_sets:
        warn("no 'bins_*' set annotated: skipping bin dosage")


def main():
    """Dispatch to the chosen subcommand."""
    args = parse_args()
    if args.command == "sample":
        summarize_sample(args)
    else:
        summarize_cohort(args)


if __name__ == "__main__":
    main()
