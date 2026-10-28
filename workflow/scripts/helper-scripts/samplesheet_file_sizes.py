#!/usr/bin/env python3
"""List the file sizes (in GB) of all input files in a workflow sample sheet.

Usage:
    samplesheet_file_sizes.py SAMPLESHEET.tsv [-o OUTPUT.tsv]

The sample sheet needs the columns 'sample' and 'input_path' (comma-separated list of files).
Output (tab-separated): one row per file with the columns sample, file, size_GB and
sample_total_GB, sorted by the total size per sample (largest first). Missing files get
'NA' as size and are reported on stderr, as is the average size per sample (missing files
count as 0).
"""

import argparse
import csv
import pathlib
import sys


def main():
    """Read the sample sheet, look up the size of every input file and write the table."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("samplesheet", type=pathlib.Path, help="sample sheet (TSV with 'sample' and 'input_path')")
    parser.add_argument("-o", "--output", type=pathlib.Path, help="output TSV (default: stdout)")
    args = parser.parse_args()

    with args.samplesheet.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))

    entries = []  # (sample, file, size in bytes or None)
    for row in rows:
        for file in row["input_path"].split(","):
            path = pathlib.Path(file.strip())
            try:
                size = path.stat().st_size
            except OSError as error:
                print(f"WARNING: cannot read size of {path}: {error}", file=sys.stderr)
                size = None
            entries.append((row["sample"], str(path), size))

    totals = {}
    counts = {}
    for sample, _, size in entries:
        totals[sample] = totals.get(sample, 0) + (size or 0)
        counts[sample] = counts.get(sample, 0) + 1
    entries.sort(key=lambda entry: (-totals[entry[0]], entry[0], entry[1]))

    out = args.output.open("w", encoding="utf-8", newline="") if args.output else sys.stdout
    try:
        writer = csv.writer(out, delimiter="\t", lineterminator="\n")
        writer.writerow(["sample", "file", "size_GB", "sample_total_GB"])
        for sample, file, size in entries:
            size_gb = "NA" if size is None else f"{size / 1e9:.1f}"
            writer.writerow([sample, file, size_gb, f"{totals[sample] / 1e9:.1f}"])
    finally:
        if args.output:
            out.close()

    average = sum(totals.values()) / len(totals)
    print(f"Average size per sample: {average / 1e9:.1f} GB ({len(totals)} samples)", file=sys.stderr)


if __name__ == "__main__":
    main()
