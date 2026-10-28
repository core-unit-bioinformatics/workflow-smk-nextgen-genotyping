#!/usr/bin/env python3
"""List rare SVs (by reference-panel allele frequency) that are homozygous in the cohort.

Inputs:
  * the merged multi-sample PanGenie VCF (after convert-to-biallelic; GT[:GQ] per sample),
    as a file or '-' for stdin;
  * the allele frequency of the reference panel, either
      - --panel-vcf: the panel VCF that was given to PanGenie (the reference callset); the AF
        is re-computed from its genotypes (the INFO/AF of the panel is not reliable) and the
        panel variants are matched to the cohort VCF via the panel's INFO/ID, or
      - --panel-table: the table of the workflow rule 'tabulate_pangenie_panel_variants'
        (proc/50-plotting/10_pangenie/pl_tab/<ref_callset>.panel-variants.tsv.gz), which
        contains the same information but only exists for runs with the plotting module.

A variant is reported if |len(ALT) - len(REF)| >= --sv-min-length, its panel AF is below
--max-panel-af and at least one cohort sample has the genotype 1/1. Low genotype
qualities are NOT filtered; the GQ is reported for every homozygous genotype so that
the list can be filtered afterwards.

Output (TSV, one row per homozygous sample genotype; variant_id is a short ID such as
chr1-597799-INS-376, the complete graph ID of the VCF is the last column):
  variant_id, chrom, start, end, sv_type, sv_length, panel_af, cohort_af, cohort_n_called,
  cohort_n_het, cohort_n_hom_alt, sample, gq, full_variant_id

To speed things up, the VCF can be pre-filtered to SVs (the script checks the length again):
  bcftools view -i 'ILEN<=-50 || ILEN>=50' merged.vcf.gz | rare_homozygous_svs.py - ...
"""

import argparse
import csv
import gzip
import sys

HEADER = (
    "variant_id",
    "chrom",
    "start",
    "end",
    "sv_type",
    "sv_length",
    "panel_af",
    "cohort_af",
    "cohort_n_called",
    "cohort_n_het",
    "cohort_n_hom_alt",
    "sample",
    "gq",
    "full_variant_id",
)


def load_rare_panel_svs(path, sv_min_length, max_panel_af):
    """Return {variant ID: panel AF} of panel variants that are SVs and rarer than the cutoff."""
    rare = {}
    n_svs = 0
    with gzip.open(path, "rt", encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            if abs(int(row["ilen"])) < sv_min_length:
                continue
            n_svs += 1
            if row["af"] != "NA" and float(row["af"]) < max_panel_af:
                rare[row["id"]] = float(row["af"])
    print(
        f"panel: {n_svs} SVs, {len(rare)} with AF < {max_panel_af}",
        file=sys.stderr,
    )
    return rare


def info_value(info, key):
    """Return the value of an INFO key (None if the key is absent)."""
    prefix = key + "="
    for item in info.split(";"):
        if item.startswith(prefix):
            return item[len(prefix) :]
    return None


def load_rare_panel_svs_from_vcf(path, sv_min_length, max_panel_af):
    """Return {INFO/ID: panel AF} of panel SVs rarer than the cutoff, AF from the genotypes."""
    rare = {}
    n_svs = 0
    with open_vcf(path) as vcf:
        for line in vcf:
            if line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t", 9)
            ref, alt = fields[3], fields[4]
            if "," in alt or abs(len(alt) - len(ref)) < sv_min_length:
                continue
            n_svs += 1
            var_id = info_value(fields[7], "ID")
            if var_id is None or len(fields) < 10:
                continue
            gt_index = fields[8].split(":").index("GT")
            n_called = n_alt = 0
            for sample_field in fields[9].split("\t"):
                alleles = genotype_alleles(sample_field.split(":")[gt_index])
                called = [allele for allele in alleles if allele != "."]
                n_called += len(called)
                n_alt += called.count("1")
            if n_called and n_alt / n_called < max_panel_af:
                rare[var_id] = n_alt / n_called
    print(
        f"panel VCF: {n_svs} SVs, {len(rare)} with AF < {max_panel_af}",
        file=sys.stderr,
    )
    return rare


def open_vcf(path):
    """Open a (gzipped) VCF for reading as text; '-' means stdin."""
    if path == "-":
        return sys.stdin
    opener = gzip.open if path.endswith(".gz") else open
    return opener(path, "rt", encoding="utf-8")


def genotype_alleles(genotype):
    """Return the list of allele strings of a GT field ('0/1' or '0|1' -> ['0', '1'])."""
    return genotype.replace("|", "/").split("/")


def main():
    """Stream the VCF and write one row per homozygous genotype of a rare SV."""
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "vcf", help="merged PanGenie VCF (.vcf or .vcf.gz), or '-' for stdin"
    )
    panel = parser.add_mutually_exclusive_group(required=True)
    panel.add_argument(
        "--panel-vcf", help="panel VCF (.vcf or .vcf.gz) given to PanGenie"
    )
    panel.add_argument(
        "--panel-table", help="panel variant table (.tsv.gz) of the plotting module"
    )
    parser.add_argument("-o", "--output", required=True, help="output TSV")
    parser.add_argument(
        "--max-panel-af",
        type=float,
        default=0.01,
        help="report SVs with a panel AF below this value (default: 0.01)",
    )
    parser.add_argument(
        "--sv-min-length",
        type=int,
        default=50,
        help="minimum |len(ALT) - len(REF)| of an SV (default: 50)",
    )
    args = parser.parse_args()

    if args.panel_vcf:
        rare_panel = load_rare_panel_svs_from_vcf(
            args.panel_vcf, args.sv_min_length, args.max_panel_af
        )
    else:
        rare_panel = load_rare_panel_svs(
            args.panel_table, args.sv_min_length, args.max_panel_af
        )

    samples = []
    n_svs = n_rare = n_reported = 0
    with (
        open_vcf(args.vcf) as vcf,
        open(args.output, "w", encoding="utf-8", newline="") as out,
    ):
        writer = csv.writer(out, delimiter="\t", lineterminator="\n")
        writer.writerow(HEADER)
        for line in vcf:
            if line.startswith("##"):
                continue
            fields = line.rstrip("\n").split("\t")
            if line.startswith("#CHROM"):
                samples = fields[9:]
                continue
            chrom, pos, var_id, ref, alt = fields[:5]
            ilen = len(alt) - len(ref)
            if "," in alt or abs(ilen) < args.sv_min_length:
                continue
            n_svs += 1
            panel_af = rare_panel.get(var_id)
            if panel_af is None:
                continue
            n_rare += 1
            format_keys = fields[8].split(":")
            gt_index = format_keys.index("GT")
            gq_index = format_keys.index("GQ") if "GQ" in format_keys else None

            n_called = n_alt_alleles = n_het = 0
            hom_samples = []
            for sample, sample_field in zip(samples, fields[9:], strict=True):
                values = sample_field.split(":")
                alleles = genotype_alleles(values[gt_index])
                called = [allele for allele in alleles if allele != "."]
                n_called += len(called)
                n_alt_alleles += called.count("1")
                if len(alleles) == 2 and set(alleles) == {"0", "1"}:
                    n_het += 1
                elif alleles == ["1", "1"]:
                    gq = "NA"
                    if gq_index is not None and gq_index < len(values):
                        gq = "NA" if values[gq_index] == "." else values[gq_index]
                    hom_samples.append((sample, gq))
            if not hom_samples:
                continue
            n_reported += 1
            cohort_af = f"{n_alt_alleles / n_called:.4f}" if n_called else "NA"
            sv_type = "deletion" if ilen < 0 else "insertion"
            end = int(pos) + len(ref) - 1
            short_id = f"{chrom}-{pos}-{sv_type[:3].upper()}-{abs(ilen)}"
            for sample, gq in hom_samples:
                writer.writerow(
                    [
                        short_id,
                        chrom,
                        pos,
                        end,
                        sv_type,
                        abs(ilen),
                        f"{panel_af:.5f}",
                        cohort_af,
                        n_called // 2,
                        n_het,
                        len(hom_samples),
                        sample,
                        gq,
                        var_id,
                    ]
                )
    print(
        f"cohort: {n_svs} SVs in the VCF, {n_rare} with panel AF < {args.max_panel_af}, "
        f"{n_reported} of them homozygous in at least one sample",
        file=sys.stderr,
    )
    print(
        "(SVs not found in the panel table or without panel AF are not reported)",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
