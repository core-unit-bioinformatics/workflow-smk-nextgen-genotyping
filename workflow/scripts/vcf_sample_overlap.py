#!/usr/bin/env python3

# example run: vcf_sample_overlap.py path/to/merged.vcf.gz

"""
vcf_sample_overlap.py

Scan a merged, multi-sample VCF (plain or bgzipped) and report:
  - total number of variant records
  - number of variants present in at least one sample
  - number of variants present in ALL samples
  - number of variants present in each exact combination of samples
  - number of variants present in NONE of the samples

"Present" means, sample's GT contains at least one ALT allele (e.g. 0/1, 1/0, 1/1)
"""

import argparse
import gzip
import itertools
import sys
from collections import Counter


def open_vcf(path):
    """Open a VCF file, transparently handling gzip/bgzip compression."""
    with open(path, "rb") as fh:
        magic = fh.read(2)
    if magic == b"\x1f\x8b":
        return gzip.open(path, "rt")
    return open(path, "rt")


def parse_samples_header(line):
    """Parse the #CHROM header line to extract sample names."""
    fields = line.rstrip("\n").split("\t")
    if len(fields) <= 9:
        raise ValueError(
            "VCF #CHROM header line has no sample columns "
            f"(found {len(fields)} columns, expected > 9)."
        )
    return fields[9:]


def genotype_alleles(gt_string):
    """Split a GT string like '0/1', '1|0', './.' into a list of alleles."""
    gt_string = gt_string.replace("|", "/")
    return gt_string.split("/")


def has_alt_allele(gt_string, mode="any"):
    """Check if a genotype string contains at least one alternate allele."""
    alleles = genotype_alleles(gt_string)
    non_missing = [a for a in alleles if a != "."]

    if not non_missing:
        return False

    if mode == "any":
        return any(a != "0" for a in non_missing)
    elif mode == "hom":
        return all(a != "0" for a in non_missing)
    else:
        raise ValueError(f"Unknown mode: {mode}")


def scan_vcf(vcf_path, mode):
    """Count the number of variants present in each combination."""
    samples = None
    gt_index_cache = {}
    combo_counts = Counter()
    total_variants = 0

    with open_vcf(vcf_path) as fh:
        for line in fh:
            if line.startswith("##"):
                continue
            if line.startswith("#CHROM"):
                samples = parse_samples_header(line)
                continue
            if samples is None:
                raise ValueError("Encountered a data line before the #CHROM header.")

            fields = line.rstrip("\n").split("\t")
            format_field = fields[8]
            sample_fields = fields[9:]

            if format_field not in gt_index_cache:
                format_keys = format_field.split(":")
                if "GT" not in format_keys:
                    raise ValueError(
                        f"FORMAT field '{format_field}' does not contain GT."
                    )
                gt_index_cache[format_field] = format_keys.index("GT")
            gt_index = gt_index_cache[format_field]

            present = []
            for sample_name, sample_data in zip(samples, sample_fields):
                gt_string = sample_data.split(":")[gt_index]
                if has_alt_allele(gt_string, mode=mode):
                    present.append(sample_name)

            combo_counts[frozenset(present)] += 1
            total_variants += 1

    if samples is None:
        raise ValueError("No #CHROM header line found - is this a valid VCF?")

    return samples, total_variants, combo_counts


def pct_of(count, denominator):
    """Calculate percentages"""
    if denominator == 0:
        return 0.0
    return 100.0 * count / denominator


def write_tsv(path, samples, total_variants, combo_counts):
    """Write the results to TSV."""
    all_samples = frozenset(samples)
    n = len(samples)
    none_count = combo_counts[frozenset()]
    present_in_at_least_one = total_variants - none_count

    combo_sum = combo_counts[all_samples]
    for size in range(n - 1, 0, -1):
        for combo in itertools.combinations(samples, size):
            combo_sum += combo_counts[frozenset(combo)]

    with open(path, "w") as out:
        out.write("GROUP\tVAR_COUNT\tPERCENTAGE\n")

        out.write("\n# overview\n")
        out.write(f"total_variants\t{total_variants}\t\n")
        out.write(f"present_in_at_least_one\t{present_in_at_least_one}\t\n")
        out.write(f"sum_of_all_combination_counts\t{combo_sum}\t\n")
        out.write(f"present_in_none\t{none_count}\t\n")

        out.write("\n# present in all\n")
        pct = pct_of(combo_counts[all_samples], present_in_at_least_one)
        out.write(f"present_in_all_samples\t{combo_counts[all_samples]}\t{pct:.2f}\n")

        for size in range(n - 1, 0, -1):
            out.write(f"\n# Exclusively present in exactly {size} sample(s)\n")
            for combo in itertools.combinations(samples, size):
                combo_set = frozenset(combo)
                count = combo_counts[combo_set]
                pct = pct_of(count, present_in_at_least_one)
                group_label = ",".join(combo)
                out.write(f"{group_label}\t{count}\t{pct:.2f}\n")


def print_report(samples, total_variants, combo_counts, mode, vcf_path):
    """Print a stats summary report."""
    all_samples = frozenset(samples)
    n = len(samples)
    none_count = combo_counts[frozenset()]
    present_in_at_least_one = total_variants - none_count

    combo_sum = combo_counts[all_samples]
    for size in range(n - 1, 0, -1):
        for combo in itertools.combinations(samples, size):
            combo_sum += combo_counts[frozenset(combo)]

    print(f"Processed {n} samples")
    print(f"Total Variants: {total_variants}")
    print(f"Present in at least one sample: {present_in_at_least_one}")
    print(f"Sum of all combination counts (sanity check): {combo_sum}")

    if combo_sum != present_in_at_least_one:
        print(
            f"WARNING: sum ({combo_sum}) does not match 'present in at least "
            f"one sample' ({present_in_at_least_one}) - something is "
            "inconsistent.",
            file=sys.stderr,
        )

    check_sum = sum(combo_counts.values())
    if check_sum != total_variants:
        print(
            f"WARNING: combination counts (incl. 'none') sum to {check_sum}, "
            f"expected {total_variants} - something is inconsistent.",
            file=sys.stderr,
        )

    print()
    print("> Finished calculating stats")


def main():
    """Main function."""
    parser = argparse.ArgumentParser(
        description="Report per-combination variant presence counts from a merged VCF."
    )
    parser.add_argument("vcf", help="Path to merged, multi-sample VCF (plain or .gz)")
    parser.add_argument("--min-genotype", choices=["any", "hom"], default="any",
                            help="'any' = at least one ALT allele present (default); "
                            "'hom' = only homozygous ALT (e.g. 1/1) present.",
    )
    parser.add_argument("--out", metavar="FILE", default="vcf_sample_stats.tsv",
        help="Writes a TSV summary (GROUP, VAR_COUNT, PERCENTAGE) to this path."
    )
    args = parser.parse_args()

    samples, total_variants, combo_counts = scan_vcf(args.vcf, args.min_genotype)

    print_report(samples, total_variants, combo_counts, args.min_genotype, args.vcf)

    if args.out:
        write_tsv(args.out, samples, total_variants, combo_counts)
        print(f"\nTSV summary written to: {args.out}\n")


if __name__ == "__main__":
    main()
