#!/usr/bin/env python3
"""
Pad each locus in a BED file to a minimum length of 30kb.

Usage:
    python3 pad_bed.py genes.bed
    python3 pad_bed.py genes.bed 50000
"""

import argparse
import sys
from pathlib import Path


def pad_line(fields, target_length):
    chrom, start, end = fields[0], int(fields[1]), int(fields[2])
    length = end - start

    if length >= target_length:
        return fields, False

    extra = target_length - length
    pad_left = extra // 2
    pad_right = extra - pad_left

    new_start = start - pad_left
    new_end = end + pad_right

    if new_start < 0:
        shortfall = -new_start
        new_start = 0
        new_end += shortfall

    fields[1] = str(new_start)
    fields[2] = str(new_end)
    return fields, True


def main():
    parser = argparse.ArgumentParser(
        description="Pad BED loci to a minimum total length."
    )
    parser.add_argument("bedfile", help="Input BED file")
    parser.add_argument(
        "target_length", nargs="?", type=int, default=30000,
        help="Minimum total locus length in bp [default: 30000]",
    )
    args = parser.parse_args()

    in_path = Path(args.bedfile)
    out_path = in_path.with_name(in_path.stem + "_padded" + in_path.suffix)

    padded_count = 0
    total_count = 0

    with open(in_path) as inp, open(out_path, "w") as out:
        for line in inp:
            stripped = line.rstrip("\n")
            if not stripped or stripped.startswith(("#", "track", "browser")):
                out.write(line)
                continue

            fields = stripped.split("\t")
            if len(fields) < 3:
                sys.stderr.write(f"WARNING: skipping malformed line (fewer than 3 columns): {stripped!r}\n")
                out.write(line)
                continue

            try:
                int(fields[1])
                int(fields[2])
            except ValueError:
                # not a normal chrom/start/end data line - pass through unchanged
                out.write(line)
                continue

            total_count += 1
            fields, was_padded = pad_line(fields, args.target_length)
            if was_padded:
                padded_count += 1
            out.write("\t".join(fields) + "\n")

    print(f"Processed {total_count} loci, padded {padded_count} to >= {args.target_length} bp")
    print(f"Output written to: {out_path}")


if __name__ == "__main__":
    main()
