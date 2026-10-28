#!/usr/bin/env python3
"""Turn 'bcftools query' output into a compact per-variant table (no allele sequences).

Expected input on stdin (tab-separated, one variant per line, '.' = missing):
    id  ref  alt  af  an  ns  ac_het
Output (gzipped TSV with header):
    id  class  ilen  af  an  ns  ac_het
where 'class' is one of snv, indel, sv, other and 'ilen' = len(alt) - len(ref).
"""

import argparse
import gzip
import sys

N_INPUT_FIELDS = 7
HEADER = ("id", "class", "ilen", "af", "an", "ns", "ac_het")


def classify(ref, alt, sv_min_length):
    """Return (class, ilen) of a biallelic variant based on its REF/ALT lengths."""
    if "," in alt or alt.startswith("<") or "*" in alt:
        return "other", 0
    ilen = len(alt) - len(ref)
    if abs(ilen) >= sv_min_length:
        return "sv", ilen
    if ilen != 0:
        return "indel", ilen
    if len(ref) == 1:
        return "snv", 0
    return "other", 0


def main():
    """Read variants from stdin and write the compact table."""
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("-o", "--output", required=True, help="output table (.tsv.gz)")
    parser.add_argument(
        "--sv-min-length",
        type=int,
        default=50,
        help="minimum |len(ALT) - len(REF)| of an SV (default: 50)",
    )
    args = parser.parse_args()

    n_variants = 0
    with gzip.open(args.output, "wt", encoding="utf-8") as out:
        out.write("\t".join(HEADER) + "\n")
        for line in sys.stdin:
            fields = line.rstrip("\n").split("\t")
            if len(fields) != N_INPUT_FIELDS:
                raise ValueError(
                    f"expected {N_INPUT_FIELDS} fields, got {len(fields)}: {line[:200]!r}"  # noqa: E501
                )
            var_id, ref, alt, af, an, ns, ac_het = fields
            var_class, ilen = classify(ref, alt, args.sv_min_length)
            values = [af, an, ns, ac_het]
            values = ["NA" if value == "." else value for value in values]
            out.write("\t".join([var_id, var_class, str(ilen), *values]) + "\n")
            n_variants += 1
    print(f"{n_variants} variants written to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
