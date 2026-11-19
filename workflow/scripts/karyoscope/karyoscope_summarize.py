#!/usr/bin/env python3
"""Condense KaryoScope per-read annotations into per-sample and cohort tables.

Subcommands:
  sample  sum the annotated k-mer bp per label and feature set for one sample
  cohort  merge the per-sample tables into cohort composition tables and a
          chromosome dosage / sex QC table
"""

import argparse
import collections
import csv
import pathlib
import statistics
import subprocess
import sys

AUTOSOMES = [f"chr{i}" for i in range(1, 23)]
CHR_X = "chrX"
CHR_Y = "chrY"
NOVEL = "novel"

# Output order of the labels per feature set (hierarchy of the CHM13 database).
# Labels not listed here follow alphabetically; "none" (chrM) and "novel" last.
LABEL_ORDER = {
    "chromosome": [
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
        "--x-diploid-share",
        type=float,
        default=0.053,
        help="expected chrX bp / autosomal bp for two X copies",
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
        help="flag a chromosome whose ratio to the cohort median deviates more",
    )
    return parser.parse_args()


def order_labels(feature_set, labels):
    """Sort labels hierarchically for a feature set, unknown ones alphabetically."""
    labels = set(labels)
    known = [lb for lb in LABEL_ORDER.get(feature_set, []) if lb in labels]
    tail = [lb for lb in TAIL_LABELS if lb in labels]
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
    feature_sets = [fs for fs in args.feature_sets.split(",") if fs]
    rows = []
    for feature_set in feature_sets:
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
    with open(args.output, "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(["sample", "feature_set", "label", "bp", "fraction"])
        writer.writerows(rows)


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


def ratio(value, reference):
    """Return value / reference, or None if the reference is missing or zero."""
    if reference is None or reference == 0:
        return None
    return value / reference


def fmt(value, digits=4):
    """Format a float for the output tables, NA for None."""
    return "NA" if value is None else f"{value:.{digits}f}"


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


def write_dosage(data, args, path):
    """Write per-sample chromosome dosage, X/Y shares, sex call and QC flags."""
    metrics = {}
    for sample, per_set in data.items():
        counts = per_set.get("chromosome", {})
        autosomal = sum(counts.get(c, 0) for c in AUTOSOMES)
        if autosomal == 0:
            raise ValueError(f"{sample}: no autosomal k-mers in the chromosome set")
        total = sum(counts.values())
        x_share = counts.get(CHR_X, 0) / autosomal
        y_share = counts.get(CHR_Y, 0) / autosomal
        x_copies = 2 * x_share / args.x_diploid_share
        y_status, sex_chromosomes, inferred_sex = call_sex_chromosomes(
            x_copies, y_share * 1e6, args
        )
        metrics[sample] = {
            "total": total,
            "autosomal": autosomal,
            "novel": counts.get(NOVEL, 0) / total,
            "share": {c: counts.get(c, 0) / autosomal for c in AUTOSOMES},
            "x_share": x_share,
            "y_share": y_share,
            "x_copies": x_copies,
            "y_status": y_status,
            "sex_chromosomes": sex_chromosomes,
            "inferred_sex": inferred_sex,
        }

    if len(metrics) < 5:
        print(
            f"[summarize] WARNING: only {len(metrics)} samples, cohort medians are "
            "not a reliable baseline for the autosome ratios",
            file=sys.stderr,
        )

    median_share = {
        c: statistics.median(m["share"][c] for m in metrics.values()) for c in AUTOSOMES
    }

    header = [
        "sample", "total_bp", "autosomal_bp", "autosomal_fraction", "novel_fraction",
        *AUTOSOMES,
        "chrX_share", "chrX_ppm", "chrY_share", "chrY_ppm",
        "x_copies", "y_status", "sex_chromosomes", "inferred_sex", "flags",
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
                f"(x_copies={m['x_copies']:.2f},y={m['y_status']})"
            )
        rows.append([
            sample, m["total"], m["autosomal"], fmt(m["autosomal"] / m["total"], 6),
            fmt(m["novel"], 6),
            *(fmt(ratios[c]) for c in AUTOSOMES),
            fmt(m["x_share"], 6), fmt(m["x_share"] * 1e6, 1),
            fmt(m["y_share"], 8), fmt(m["y_share"] * 1e6, 1),
            fmt(m["x_copies"], 2), m["y_status"], m["sex_chromosomes"],
            m["inferred_sex"], ";".join(flags) if flags else ".",
        ])  # fmt: skip
    write_tsv(path, header, rows)


def summarize_cohort(args):
    """Write one composition table per feature set plus the dosage table."""
    data = read_sample_tables(args.inputs)
    args.outdir.mkdir(parents=True, exist_ok=True)
    for feature_set in [fs for fs in args.feature_sets.split(",") if fs]:
        out = args.outdir.joinpath(f"SAMPLES.{feature_set}.composition.tsv")
        write_composition(data, feature_set, out)
    write_dosage(data, args, args.outdir.joinpath("SAMPLES.chromosome_dosage.tsv"))


def main():
    """Dispatch to the chosen subcommand."""
    args = parse_args()
    if args.command == "sample":
        summarize_sample(args)
    else:
        summarize_cohort(args)


if __name__ == "__main__":
    main()