#!/usr/bin/env python3
"""Create a per-sample SV count table from 'bcftools +smpl-stats' outputs.

Each of the three input files (all SVs, deletions only, insertions only) is
parsed for its FLT0 lines. A sample carries an SV if its genotype is 0/1 or 1/1,
i.e. n_carried is the number of non-reference genotypes.
('bcftools stats' is not used because it only counts variants that it classifies
as SNPs/indels, which misses SVs without a shared anchor base.)

Output (TSV with header): sample, sv_class, n_het, n_homalt, n_carried
where sv_class is one of: all, deletion, insertion.
"""

import argparse
import csv

HEADER = ("sample", "sv_class", "n_het", "n_homalt", "n_carried")
# 0-based column indices of the FLT0 lines of 'bcftools +smpl-stats'
COL_SAMPLE = 1
COL_NONREF = 3
COL_HOMALT = 5
COL_HET = 6


def parse_smpl_stats(path):
    """Return {sample: (n_het, n_homalt, n_nonref)} from the FLT0 lines of a smpl-stats file."""  # noqa: E501
    counts = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if not line.startswith("FLT0\t"):
                continue
            fields = line.rstrip("\n").split("\t")
            counts[fields[COL_SAMPLE]] = (
                int(fields[COL_HET]),
                int(fields[COL_HOMALT]),
                int(fields[COL_NONREF]),
            )
    if not counts:
        raise ValueError(
            f"no FLT0 lines found in {path} (was 'bcftools +smpl-stats' used?)"
        )
    return counts


def main():
    """Parse the three stats files and write the combined table."""
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--stats-all", required=True, help="smpl-stats of all SVs")
    parser.add_argument("--stats-del", required=True, help="smpl-stats of deletions")
    parser.add_argument("--stats-ins", required=True, help="smpl-stats of insertions")
    parser.add_argument("-o", "--output", required=True, help="output TSV")
    args = parser.parse_args()

    stats = {
        "all": parse_smpl_stats(args.stats_all),
        "deletion": parse_smpl_stats(args.stats_del),
        "insertion": parse_smpl_stats(args.stats_ins),
    }
    samples = list(stats["all"])
    for sv_class, counts in stats.items():
        if list(counts) != samples:
            raise ValueError(
                f"sample lists differ between the stats files (class: {sv_class})"
            )

    with open(args.output, "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(HEADER)
        for sv_class, counts in stats.items():
            for sample in samples:
                n_het, n_homalt, n_nonref = counts[sample]
                writer.writerow([sample, sv_class, n_het, n_homalt, n_nonref])


if __name__ == "__main__":
    main()
