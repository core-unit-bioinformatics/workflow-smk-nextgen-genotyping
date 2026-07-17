#!/usr/bin/env python3

# example run: vcf_sample_overlap.py path/to/merged.vcf.gz --out summary.tsv

"""
vcf_sample_overlap.py

Compare genotypes across a merged VCF containing 3 samples

  1. Classify special missingness patterns. A genotype counts as
     "missing" if ANY of its alleles is '.' (covers both fully
     missing './.' and partially-missing genotypes like '0/.'):
     - missing in all 3 samples
     - missing in both short-read samples, but not HiFi
     - missing in HiFi, but not in either short-read sample
  2. For all remaining variants, compare each of the 3 sample pairs
     (short1-short2, short1-hifi, short2-hifi) and count matches 
     (allele order ignored, since input is unphased) vs. mismatches.
  3. For ALL variants, produce a 4x4 confusion matrix for each 
     sample pair, with the categories: 0/0, 0/1, 1/1, ./.
  4. Extract variants present in BOTH short-read samples only
     and variants present in HiFi only. 

Produces a TSV with overview stats plus match/mismatch matrices
"""

import argparse
import collections
import gzip
import sys


def open_vcf(path):
    """Open a VCF file, transparently handling gzip/bgzip compression."""
    with open(path, "rb") as fh:
        magic = fh.read(2)
    if magic == b"\x1f\x8b":
        return gzip.open(path, "rt")
    return open(path, "rt")


def open_output_vcf(path):
    """Open an output VCF for writing."""
    if path.endswith(".gz"):
        return gzip.open(path, "wt")
    return open(path, "w")


def parse_samples_header(line):
    """Extract sample names from #CHROM header."""
    fields = line.rstrip("\n").split("\t")
    if len(fields) <= 9:
        raise ValueError(
            "VCF #CHROM header line has no sample columns "
            f"(found {len(fields)} columns, expected > 9)."
        )
    return fields[9:]


def identify_sample_roles(samples):
    """Identify the 2 short-read samples and the 1 HiFi sample based
    on matching "short" or "hifi" to the sample name."""
    short_samples = [s for s in samples if "short" in s.lower()]
    hifi_samples = [s for s in samples if "hifi" in s.lower()]

    if len(short_samples) != 2:
        raise ValueError(
            f"Expected exactly 2 samples with 'short' in their name, "
            f"found {len(short_samples)}: {short_samples}"
        )
    if len(hifi_samples) != 1:
        raise ValueError(
            f"Expected exactly 1 sample with 'hifi' in their name, "
            f"found {len(hifi_samples)}: {hifi_samples}"
        )
    if set(short_samples) & set(hifi_samples):
        raise ValueError(
            f"Sample(s) matched both 'short' and 'hifi' patterns: "
            f"{set(short_samples) & set(hifi_samples)}"
        )
    if len(samples) != 3:
        raise ValueError(
            f"Expected exactly 3 samples total (2 short + 1 hifi), "
            f"found {len(samples)}: {samples}"
        )

    return short_samples[0], short_samples[1], hifi_samples[0]


def parse_genotype(gt_string):
    """Return a normalized, sorted alleles for a GT string.
    '|' is normalized to '/' (data is unphased). 
    Sorting means '0/1' and '1/0' are identical."""
    alleles = gt_string.replace("|", "/").split("/")
    return tuple(sorted(alleles))


def is_missing(gt_tuple):
    """Check (partially) missing genotypes."""

    return any(a == "." for a in gt_tuple)


GENOTYPE_CATEGORIES = ["0/0", "0/1", "1/1", "./."]


def genotype_category(gt_tuple):
    """Map a normalized genotype tuple to one of the 4 confusion-matrix
    categories. A genotype that isn't 0/0, 0/1, or 1/1 (e.g. a multi-
    allelic call like 1/2) is returned as 'other' and reported separately."""
    if is_missing(gt_tuple):
        return "./."
    label = "/".join(gt_tuple)
    if label in ("0/0", "0/1", "1/1"):
        return label
    return "other"


def genotypes_match(gt_a, gt_b):
    """Check matching genotypes."""

    if any(a == "." for a in gt_a) or any(a == "." for a in gt_b):
        return False
    return gt_a == gt_b


def scan_vcf(vcf_path, out_short=None, out_hifi=None):
    samples = None
    short1 = short2 = hifi = None
    gt_index_cache = {}
    header_lines = []

    total_variants = 0
    missing_all = 0
    missing_both_short_not_hifi = 0
    missing_hifi_not_both_short = 0
    identical_all3 = 0
    match_counts = collections.Counter()
    mismatch_counts = collections.Counter()
    confusion_counts = collections.defaultdict(collections.Counter)
    other_genotypes_seen = set()

    both_short_out = open_output_vcf(out_short) if out_short else None
    hifi_only_out = open_output_vcf(out_hifi) if out_hifi else None
    headers_written = False

    try:
        with open_vcf(vcf_path) as fh:
            for line in fh:
                if line.startswith("##"):
                    header_lines.append(line)
                    continue
                if line.startswith("#CHROM"):
                    header_lines.append(line)
                    samples = parse_samples_header(line)
                    short1, short2, hifi = identify_sample_roles(samples)
                    if both_short_out:
                        both_short_out.writelines(header_lines)
                    if hifi_only_out:
                        hifi_only_out.writelines(header_lines)
                    headers_written = True
                    continue
                if samples is None:
                    raise ValueError("Encountered a data line before the #CHROM header.")

                fields = line.rstrip("\n").split("\t")
                format_field = fields[8]
                sample_fields = fields[9:]

                if format_field not in gt_index_cache:
                    format_keys = format_field.split(":")
                    if "GT" not in format_keys:
                        raise ValueError(f"FORMAT field '{format_field}' does not contain GT.")
                    gt_index_cache[format_field] = format_keys.index("GT")
                gt_index = gt_index_cache[format_field]

                gt_by_sample = {}
                for sample_name, sample_data in zip(samples, sample_fields):
                    gt_string = sample_data.split(":")[gt_index]
                    gt_by_sample[sample_name] = parse_genotype(gt_string)

                total_variants += 1

                gt_short1 = gt_by_sample[short1]
                gt_short2 = gt_by_sample[short2]
                gt_hifi = gt_by_sample[hifi]

                miss_short1 = is_missing(gt_short1)
                miss_short2 = is_missing(gt_short2)
                miss_hifi = is_missing(gt_hifi)

                pair_genotypes = [
                    (short1, short2, gt_short1, gt_short2),
                    (short1, hifi, gt_short1, gt_hifi),
                    (short2, hifi, gt_short2, gt_hifi),
                ]

                # confusion matrix. every variant, regardless of missingness 
                for name_a, name_b, gt_a, gt_b in pair_genotypes:
                    cat_a = genotype_category(gt_a)
                    cat_b = genotype_category(gt_b)
                    confusion_counts[(name_a, name_b)][(cat_a, cat_b)] += 1
                    if cat_a == "other":
                        other_genotypes_seen.add("/".join(gt_a))
                    if cat_b == "other":
                        other_genotypes_seen.add("/".join(gt_b))

                # classify missingness patterns
                if miss_short1 and miss_short2 and miss_hifi:
                    missing_all += 1
                    continue

                if miss_short1 and miss_short2 and not miss_hifi:
                    # present in HiFi, missing in BOTH short-read samples
                    missing_both_short_not_hifi += 1
                    if hifi_only_out:
                        hifi_only_out.write(line)
                    continue

                if miss_hifi and not miss_short1 and not miss_short2:
                    # present in BOTH short-read samples, missing in HiFi
                    missing_hifi_not_both_short += 1
                    if both_short_out:
                        both_short_out.write(line)
                    continue

                # remaining variants > pairwise match/mismatch ---
                all_match = True
                for name_a, name_b, gt_a, gt_b in pair_genotypes:
                    pair_key = frozenset((name_a, name_b))
                    if genotypes_match(gt_a, gt_b):
                        match_counts[pair_key] += 1
                    else:
                        mismatch_counts[pair_key] += 1
                        all_match = False

                if all_match:
                    identical_all3 += 1
    finally:
        if both_short_out:
            both_short_out.close()
        if hifi_only_out:
            hifi_only_out.close()

    if samples is None:
        raise ValueError("No #CHROM header line found - is this a valid VCF?")
    if not headers_written and (both_short_out or hifi_only_out):
        raise ValueError("No #CHROM header line was found - extraction VCF(s) would be headerless.")

    return {
        "samples": samples,
        "short1": short1,
        "short2": short2,
        "hifi": hifi,
        "total_variants": total_variants,
        "missing_all": missing_all,
        "missing_both_short_not_hifi": missing_both_short_not_hifi,
        "missing_hifi_not_both_short": missing_hifi_not_both_short,
        "identical_all3": identical_all3,
        "match_counts": match_counts,
        "mismatch_counts": mismatch_counts,
        "confusion_counts": confusion_counts,
        "other_genotypes_seen": other_genotypes_seen,
    }


def pct_of(count, denominator):
    """Calculate percentages"""
    if denominator == 0:
        return 0.0
    return 100.0 * count / denominator


def validate_stats(stats):
    """Sanity-check that all counters are internally consistent:
    Returns (remaining_count, list_of_problem_strings). An empty
    problem list means everything checks out."""
    total = stats["total_variants"]
    accounted = (
        stats["missing_all"]
        + stats["missing_both_short_not_hifi"]
        + stats["missing_hifi_not_both_short"]
    )
    remaining = total - accounted
    problems = []

    if remaining < 0:
        problems.append(
            f"Special missingness categories sum to {accounted}, "
            f"which exceeds total_variants ({total})."
        )

    pairs = [
        frozenset((stats["short1"], stats["short2"])),
        frozenset((stats["short1"], stats["hifi"])),
        frozenset((stats["short2"], stats["hifi"])),
    ]
    for pair in pairs:
        pair_total = stats["match_counts"][pair] + stats["mismatch_counts"][pair]
        if pair_total != remaining:
            problems.append(
                f"Pair {tuple(pair)}: match ({stats['match_counts'][pair]}) + "
                f"mismatch ({stats['mismatch_counts'][pair]}) = {pair_total}, "
                f"expected {remaining} (= total_variants - special missingness categories)."
            )

    for pair in pairs:
        pair_matches = stats["match_counts"][pair]
        if stats["identical_all3"] > pair_matches:
            problems.append(
                f"identical_all3 ({stats['identical_all3']}) exceeds match count "
                f"for pair {tuple(pair)} ({pair_matches})."
            )

    return remaining, problems


def write_matrix(out, samples, pair_counts, total):
    out.write("GROUP\t" + "\t".join(samples) + "\n")
    for row_sample in samples:
        row_cells = []
        for col_sample in samples:
            if row_sample == col_sample:
                row_cells.append("-")
                continue
            count = pair_counts[frozenset((row_sample, col_sample))]
            pct = pct_of(count, total)
            row_cells.append(f"{count} ({pct:.2f}%)")
        out.write(row_sample + "\t" + "\t".join(row_cells) + "\n")


def write_confusion_matrix(out, row_sample, col_sample, counts):
    out.write(f"\n# confusion matrix: {row_sample} (rows) vs {col_sample} (columns)\n")
    out.write("GENOTYPE\t" + "\t".join(GENOTYPE_CATEGORIES) + "\n")
    for cat_row in GENOTYPE_CATEGORIES:
        row_cells = [str(counts[(cat_row, cat_col)]) for cat_col in GENOTYPE_CATEGORIES]
        out.write(cat_row + "\t" + "\t".join(row_cells) + "\n")


def write_tsv(path, stats, remaining):
    samples = stats["samples"]
    total = stats["total_variants"]

    with open(path, "w") as out:
        out.write("GROUP\tVAR_COUNT\tPERCENTAGE\n")

        out.write("\n# overview\n")
        out.write(f"total_variants\t{total}\t\n")
        out.write(
            f"missing_in_all_3\t{stats['missing_all']}\t"
            f"{pct_of(stats['missing_all'], total):.2f}\n"
        )
        out.write(
            f"missing_in_both_short_not_hifi\t{stats['missing_both_short_not_hifi']}\t"
            f"{pct_of(stats['missing_both_short_not_hifi'], total):.2f}\n"
        )
        out.write(
            f"missing_in_hifi_not_both_short\t{stats['missing_hifi_not_both_short']}\t"
            f"{pct_of(stats['missing_hifi_not_both_short'], total):.2f}\n"
        )
        out.write(
            f"identical_in_all_3\t{stats['identical_all3']}\t"
            f"{pct_of(stats['identical_all3'], total):.2f}\n"
        )

        out.write("\n# match matrix (cell = count and percentage of total variants)\n")
        write_matrix(out, samples, stats["match_counts"], total)

        out.write("\n# mismatch matrix (cell = count and percentage of total variants)\n")
        write_matrix(out, samples, stats["mismatch_counts"], total)

        for name_a, name_b in [
            (stats["short1"], stats["short2"]),
            (stats["short1"], stats["hifi"]),
            (stats["short2"], stats["hifi"]),
        ]:
            write_confusion_matrix(out, name_a, name_b, stats["confusion_counts"][(name_a, name_b)])


def print_report(stats):
    n = len(stats["samples"])
    total = stats["total_variants"]
    identical = stats["identical_all3"]

    print(f"Processed {n} samples")
    print(f"Total variants: {total}")
    print(f"Identical in all 3 samples: {identical} ({pct_of(identical, total):.2f}%)")


def main():
    """Main function."""
    parser = argparse.ArgumentParser(
        description="Compare genotypes across a 2x short-read + 1x HiFi merged VCF trio."
    )
    parser.add_argument("vcf", help="Path to merged, multi-sample VCF (plain or .gz)")
    parser.add_argument(
        "--out", metavar="FILE", default="vcf_sample_stats.tsv",
        help="Path to write the TSV summary (overview stats + match/mismatch matrices).",
    )
    parser.add_argument(
        "--out-short", metavar="FILE", default=None,
        help="If given, write variants present in BOTH short-read samples only).",
    )
    parser.add_argument(
        "--out-hifi", metavar="FILE", default=None,
        help="If given, write variants present in HiFi samples only.",
    )
    args = parser.parse_args()

    stats = scan_vcf(
        args.vcf,
        out_short=args.out_short,
        out_hifi=args.out_hifi,
    )
    print_report(stats)

    remaining, problems = validate_stats(stats)
    write_tsv(args.out, stats, remaining)
    print(f"\nTSV summary written to: {args.out}")

    if args.out_short:
        print(
            f"Variants present in both short-read samples, missing in HiFi "
            f"({stats['missing_hifi_not_both_short']}) written to: {args.out_short}"
        )
    if args.out_hifi:
        print(
            f"Variants present in HiFi, missing in both short-read samples "
            f"({stats['missing_both_short_not_hifi']}) written to: {args.out_hifi}"
        )

    if stats["other_genotypes_seen"]:
        print(
            f"\nWARNING: encountered genotype(s) outside 0/0, 0/1, 1/1, ./. "
            f"(counted separately, not shown in the 4x4 confusion matrices): "
            f"{sorted(stats['other_genotypes_seen'])}",
            file=sys.stderr,
        )

    if problems:
        print("\nSANITY CHECK FAILED:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
    else:
        print("Sanity check passed: all counts are internally consistent.")


if __name__ == "__main__":
    main()