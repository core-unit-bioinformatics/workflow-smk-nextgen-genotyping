#!/usr/bin/env python3
"""Condense KaryoScope per-read annotations into per-sample and cohort tables.

Subcommands:
  sample  sum the annotated k-mer bp per label and feature set for one sample
  cohort  merge the per-sample tables into cohort tables:
            SAMPLES.<set>.composition.tsv   per set, fraction per label
            SAMPLES.chromosome_dosage.tsv   needs 'chromosome': dosage, sex call
            SAMPLES.arm_dosage.tsv          needs 'cytoband': dosage per arm
            SAMPLES.cytoband_dosage.tsv     needs 'cytoband': dosage per band
            SAMPLES.<bins>_dosage.tsv       needs a 'bins_*' set: dosage per bin
          Tables whose feature set was not annotated are skipped with a warning.
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
    coh.add_argument(
        "--reference-samples",
        default="",
        help="comma-separated samples whose median is the baseline (default: all)",
    )
    coh.add_argument(
        "--male-y-ppm",
        type=float,
        default=1000.0,
        help="chrY ppm of autosomal bp at or above which Y counts as present",
    )
    coh.add_argument(
        "--female-y-ppm",
        type=float,
        default=500.0,
        help="chrY ppm of autosomal bp at or below which Y counts as absent",
    )
    coh.add_argument(
        "--x-diploid-ppm",
        type=float,
        default=53000.0,
        help="expected chrX ppm of autosomal bp for two X copies",
    )
    coh.add_argument(
        "--y-haploid-ppm",
        type=float,
        default=3500.0,
        help="expected chrY ppm of autosomal bp for ONE Y copy (display only)",
    )
    coh.add_argument(
        "--x-copy-tolerance",
        type=float,
        default=0.25,
        help="max distance of the X copy estimate from a whole number",
    )
    coh.add_argument(
        "--max-deviation",
        type=float,
        default=0.2,
        help="flag a ratio to the reference median that deviates more than this",
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


def ratio(value, reference):
    """Return value / reference, or None if the reference is missing or zero."""
    if reference is None or reference == 0:
        return None
    return value / reference


def fmt(value, digits=4):
    """Format a float for the output tables, NA for None."""
    return "NA" if value is None else f"{value:.{digits}f}"


def flag(value, max_deviation):
    """Return 'gain', 'loss' or '.' for a ratio to the reference median."""
    if value is None or abs(value - 1) <= max_deviation:
        return "."
    return "gain" if value > 1 else "loss"


def reference_medians(shares, reference):
    """Median per key over the reference samples ({sample: {key: share}})."""
    keys = {key for per_sample in shares.values() for key in per_sample}
    return {
        key: statistics.median(shares[s].get(key, 0.0) for s in reference)
        for key in keys
    }


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


def call_sex_chromosomes(x_copies, y_ppm, args):
    """Return (y_status, sex_chromosomes, inferred_sex) from X dosage and Y signal."""
    if y_ppm >= args.male_y_ppm:
        y_status = "present"
    elif y_ppm <= args.female_y_ppm:
        y_status = "absent"
    else:
        y_status = "ambiguous"

    x_count = round(x_copies)
    if x_count < 1 or abs(x_copies - x_count) > args.x_copy_tolerance:
        x_count = None

    if x_count is None or y_status == "ambiguous":
        return y_status, "ambiguous", "ambiguous"
    sex_chromosomes = "X" * x_count + ("Y" if y_status == "present" else "")
    if sex_chromosomes == "X":
        sex_chromosomes = "X0"
    inferred_sex = {"XX": "female", "XY": "male"}.get(sex_chromosomes, "atypical")
    return y_status, sex_chromosomes, inferred_sex


def write_chromosome_dosage(data, reference, args, path):
    """Write per-sample chromosome dosage, X/Y ppm and copies, sex call, flags."""
    metrics = {}
    for sample, per_set in data.items():
        counts = per_set.get(CHROMOSOME_SET, {})
        autosomal = sum(counts.get(c, 0) for c in AUTOSOMES)
        if autosomal == 0:
            raise ValueError(f"{sample}: no autosomal k-mers in the chromosome set")
        total = sum(counts.values())
        x_ppm = counts.get(CHR_X, 0) / autosomal * 1e6
        y_ppm = counts.get(CHR_Y, 0) / autosomal * 1e6
        x_copies = 2 * x_ppm / args.x_diploid_ppm
        y_copies = y_ppm / args.y_haploid_ppm
        y_status, sex_chromosomes, inferred_sex = call_sex_chromosomes(
            x_copies, y_ppm, args
        )
        metrics[sample] = {
            "total": total,
            "autosomal": autosomal,
            "novel": counts.get(NOVEL, 0) / total,
            "share": {c: counts.get(c, 0) / autosomal for c in AUTOSOMES},
            "x_ppm": x_ppm,
            "y_ppm": y_ppm,
            "x_copies": x_copies,
            "y_copies": y_copies,
            "y_status": y_status,
            "sex_chromosomes": sex_chromosomes,
            "inferred_sex": inferred_sex,
        }

    median_share = reference_medians(
        {s: m["share"] for s, m in metrics.items()}, reference
    )
    header = [
        "sample", "total_bp", "autosomal_bp", "autosomal_fraction", "novel_fraction",
        *AUTOSOMES,
        "chrX_ppm", "chrX_copies",
        "chrY_ppm", "chrY_copies",
        "sex_chromosomes", "inferred_sex", "flags",
    ]  # fmt: skip
    rows = []
    for sample in sorted(metrics):
        m = metrics[sample]
        ratios = {c: ratio(m["share"][c], median_share[c]) for c in AUTOSOMES}
        flags = [
            f"{c}:{r:.2f}"
            for c, r in ratios.items()
            if r is not None and abs(r - 1) > args.max_deviation
        ]
        if m["sex_chromosomes"] not in ("XX", "XY"):
            flags.append(
                f"sex:{m['sex_chromosomes']}"
                f"(chrX_copies={m['x_copies']:.2f},chrY_copies={m['y_copies']:.2f},"
                f"y={m['y_status']})"
            )
        rows.append([
            sample, m["total"], m["autosomal"], fmt(m["autosomal"] / m["total"], 6),
            fmt(m["novel"], 6),
            *(fmt(ratios[c]) for c in AUTOSOMES),
            fmt(m["x_ppm"], 1), fmt(m["x_copies"], 2),
            fmt(m["y_ppm"], 1), fmt(m["y_copies"], 2),
            m["sex_chromosomes"],
            m["inferred_sex"], ";".join(flags) if flags else ".",
        ])  # fmt: skip
    write_tsv(path, header, rows)


def cytoband_shares(data):
    """Return per-sample band and arm bp, autosomal bp, and shares of it."""
    result = {}
    for sample, per_set in data.items():
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
        if autosomal == 0:
            raise ValueError(f"{sample}: no autosomal k-mers in the cytoband set")
        result[sample] = {"bands": bands, "arms": arms, "autosomal": autosomal}
    return result


def arm_names():
    """All arms in genomic order: 1p, 1q, ..., Xp, Xq, Yp, Yq."""
    return [f"{c.removeprefix('chr')}{arm}" for c in CHROMOSOMES for arm in "pq"]


def write_arm_dosage(cyto, reference, args, path):
    """Write per-sample dosage per autosomal arm, X/Y arms as ppm, and flags."""
    arms = arm_names()
    autosomal_arms = [a for a in arms if not a.startswith(("X", "Y"))]
    sex_arms = [a for a in arms if a.startswith(("X", "Y"))]
    shares = {
        s: {a: c["arms"].get(a, 0) / c["autosomal"] for a in arms}
        for s, c in cyto.items()
    }
    median = reference_medians(shares, reference)
    header = [
        "sample", "autosomal_bp", *autosomal_arms,
        *(f"{a}_ppm" for a in sex_arms), "flags",
    ]  # fmt: skip
    rows = []
    for sample in sorted(cyto):
        ratios = {a: ratio(shares[sample][a], median[a]) for a in autosomal_arms}
        flags = [
            f"{a}:{r:.2f}"
            for a, r in ratios.items()
            if r is not None and abs(r - 1) > args.max_deviation
        ]
        rows.append([
            sample, cyto[sample]["autosomal"],
            *(fmt(ratios[a]) for a in autosomal_arms),
            *(fmt(shares[sample][a] * 1e6, 1) for a in sex_arms),
            ";".join(flags) if flags else ".",
        ])  # fmt: skip
    write_tsv(path, header, rows)


def write_cytoband_dosage(cyto, reference, args, path):
    """Write a long table: one row per sample and band, with ppm, ratio, flag."""
    shares = {
        s: {b: bp / c["autosomal"] for b, bp in c["bands"].items()}
        for s, c in cyto.items()
    }
    median = reference_medians(shares, reference)
    labels = sorted(median, key=cytoband_key)
    rows = []
    for sample in sorted(cyto):
        for label in labels:
            chrom, arm, band = parse_cytoband(label)
            share = shares[sample].get(label, 0.0)
            value = ratio(share, median[label]) if chrom in AUTOSOMES else None
            rows.append([
                sample, chrom, f"{chrom.removeprefix('chr')}{arm}", label,
                cyto[sample]["bands"].get(label, 0), fmt(share * 1e6, 1),
                fmt(value), flag(value, args.max_deviation),
            ])  # fmt: skip
    header = ["sample", "chrom", "arm", "band", "bp", "ppm", "ratio", "flag"]
    write_tsv(path, header, rows)


def write_bins_dosage(data, feature_set, reference, args, path):
    """Write a long table: one row per sample and bin, with ppm, ratio, flag."""
    shares, bin_bp = {}, {}
    for sample, per_set in data.items():
        counts = per_set.get(feature_set, {})
        bins = {lb: bp for lb, bp in counts.items() if parse_bin(lb)}
        # bins plus the chromosome nodes (k-mers shared between bins of one
        # chromosome) of the autosomes
        autosomal = sum(bp for lb, bp in counts.items() if bins_chrom(lb) in AUTOSOMES)
        if autosomal == 0:
            raise ValueError(f"{sample}: no autosomal k-mers in the {feature_set} set")
        bin_bp[sample] = bins
        shares[sample] = {lb: bp / autosomal for lb, bp in bins.items()}
    median = reference_medians(shares, reference)
    labels = sorted(median, key=bin_key)
    rows = []
    for sample in sorted(data):
        for label in labels:
            chrom, start, end = parse_bin(label)
            share = shares[sample].get(label, 0.0)
            value = ratio(share, median[label]) if chrom in AUTOSOMES else None
            rows.append([
                sample, chrom, start, end, bin_bp[sample].get(label, 0),
                fmt(share * 1e6, 1), fmt(value), flag(value, args.max_deviation),
            ])  # fmt: skip
    header = ["sample", "chrom", "start", "end", "bp", "ppm", "ratio", "flag"]
    write_tsv(path, header, rows)


def select_reference(data, text):
    """Return the reference samples (default: all), checking they exist."""
    if not text:
        reference = sorted(data)
    else:
        requested = [s for s in text.split(",") if s]
        reference = [s for s in requested if s in data]
        missing = sorted(set(requested) - set(reference))
        if missing:
            warn(f"reference samples not in this run, ignored: {', '.join(missing)}")
        if not reference:
            raise ValueError("none of the --reference-samples are in this run")
    if len(reference) < 5:
        warn(
            f"only {len(reference)} reference samples: their median is not a "
            "reliable baseline for the dosage ratios"
        )
    print(f"[summarize] baseline: median of {len(reference)} samples", file=sys.stderr)
    return reference


def summarize_cohort(args):
    """Write the composition tables and every dosage table the sets allow."""
    data = read_sample_tables(args.inputs)
    feature_sets = split_sets(args.feature_sets)
    reference = select_reference(data, args.reference_samples)
    outdir = args.outdir
    outdir.mkdir(parents=True, exist_ok=True)

    for feature_set in feature_sets:
        if not has_long_dosage(feature_set):
            out = outdir.joinpath(f"SAMPLES.{feature_set}.composition.tsv")
            write_composition(data, feature_set, out)

    if CHROMOSOME_SET in feature_sets:
        out = outdir.joinpath("SAMPLES.chromosome_dosage.tsv")
        write_chromosome_dosage(data, reference, args, out)
    else:
        warn("'chromosome' not annotated: skipping chromosome dosage and sex call")

    if CYTOBAND_SET in feature_sets:
        cyto = cytoband_shares(data)
        out = outdir.joinpath("SAMPLES.arm_dosage.tsv")
        write_arm_dosage(cyto, reference, args, out)
        out = outdir.joinpath("SAMPLES.cytoband_dosage.tsv")
        write_cytoband_dosage(cyto, reference, args, out)
    else:
        warn("'cytoband' not annotated: skipping arm and band dosage")

    bins_sets = [fs for fs in feature_sets if is_bins_set(fs)]
    for feature_set in bins_sets:
        out = outdir.joinpath(f"SAMPLES.{feature_set}_dosage.tsv")
        write_bins_dosage(data, feature_set, reference, args, out)
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
