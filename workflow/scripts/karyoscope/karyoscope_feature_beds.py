#!/usr/bin/env python3
"""Prepare the custom feature sets of the workflow's KaryoScope database.

Subcommands:
  arms  insert an arm level (1p, 1q, ...) into the hierarchy and colours files
        that 'karyoscope prep-bed cytoband' wrote (band -> band group -> arm ->
        chromosome), so k-mers shared within one arm resolve to that arm
  bins  write a feature-set BED of fixed-size bins (labels chr1_0_1000000, ...)
        plus its hierarchy (bin -> chromosome -> categorized) from a .fai
"""

import argparse
import csv
import pathlib
import re

ROOT = "categorized"
# a cytoband label below chromosome level: 1p36.33, 1p36, 1q12, Xq28, ...
BAND_RE = re.compile(r"^(\d+|X|Y)([pq])[\d.]+$")
DEFAULT_PRIMARY = r"^chr(\d+|X|Y)$"


def parse_args():
    """Parse the command line."""
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    arms = sub.add_parser("arms", help="add arm nodes to a cytoband hierarchy")
    arms.add_argument("--hierarchy", required=True, type=pathlib.Path)
    arms.add_argument("--colors", type=pathlib.Path, help="colours file to extend")

    bins = sub.add_parser("bins", help="fixed-size bins as a feature set")
    bins.add_argument("--fai", required=True, type=pathlib.Path)
    bins.add_argument("--bin-size", required=True, type=int, help="in bp")
    bins.add_argument("--output", required=True, type=pathlib.Path)
    bins.add_argument("--hierarchy", required=True, type=pathlib.Path)
    bins.add_argument(
        "--primary-pattern",
        default=DEFAULT_PRIMARY,
        help="sequences to bin (default: chr1-22, chrX, chrY)",
    )
    return parser.parse_args()


def read_edges(path):
    """Read a 2-column child<TAB>parent hierarchy into an ordered list."""
    with open(path, encoding="utf-8") as handle:
        return [
            tuple(line.rstrip("\n").split("\t")[:2])
            for line in handle
            if line.strip() and not line.startswith("#")
        ]


def write_edges(path, edges):
    """Write a 2-column child<TAB>parent hierarchy."""
    with open(path, "w", encoding="utf-8") as handle:
        for child, parent in edges:
            handle.write(f"{child}\t{parent}\n")


def add_arms(args):
    """Re-parent every band or band group from its chromosome to its arm."""
    edges = read_edges(args.hierarchy)
    nodes = {child for child, _parent in edges}
    arm_nodes = {}
    new_edges = []
    for child, parent in edges:
        match = BAND_RE.match(child)
        if match and parent == match.group(1):
            arm = f"{match.group(1)}{match.group(2)}"
            if arm in nodes:
                raise ValueError(f"arm node {arm!r} already exists in {args.hierarchy}")
            if arm not in arm_nodes:
                arm_nodes[arm] = parent
                new_edges.append((arm, parent))
            new_edges.append((child, arm))
        else:
            new_edges.append((child, parent))
    if not arm_nodes:
        raise ValueError(f"no band -> chromosome edges found in {args.hierarchy}")
    write_edges(args.hierarchy, new_edges)
    print(f"[feature_beds] added {len(arm_nodes)} arm nodes to {args.hierarchy}")

    if args.colors:
        add_arm_colors(args.colors, arm_nodes)


def add_arm_colors(path, arm_nodes):
    """Give each new arm node the colour row of its chromosome node."""
    with open(path, encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle, delimiter="\t")
        header = next(reader)
        rows = list(reader)
    by_feature = {row[1]: row for row in rows}
    for arm, chrom in arm_nodes.items():
        if arm in by_feature:
            continue
        template = by_feature.get(chrom) or by_feature.get(ROOT)
        if template is None:
            raise ValueError(f"no colour row for {chrom!r} or {ROOT!r} in {path}")
        rows.append([template[0], arm, *template[2:]])
    with open(path, "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)
    print(f"[feature_beds] added colours for the arm nodes to {path}")


def make_bins(args):
    """Write fixed-size bins of the primary sequences and their hierarchy."""
    primary = re.compile(args.primary_pattern)
    n_bins = 0
    edges = []
    with (
        open(args.fai, encoding="utf-8") as fai,
        open(args.output, "w", encoding="utf-8") as bed,
    ):
        for line in fai:
            chrom, length = line.split("\t")[:2]
            if not primary.match(chrom):
                continue
            length = int(length)
            edges.append((chrom, ROOT))
            for start in range(0, length, args.bin_size):
                end = min(start + args.bin_size, length)
                label = f"{chrom}_{start}_{end}"
                bed.write(f"{chrom}\t{start}\t{end}\t{label}\n")
                edges.append((label, chrom))
                n_bins += 1
    if not n_bins:
        raise ValueError(f"no sequence in {args.fai} matches {args.primary_pattern!r}")
    write_edges(args.hierarchy, edges)
    print(f"[feature_beds] wrote {n_bins} bins of {args.bin_size} bp to {args.output}")


def main():
    """Dispatch to the chosen subcommand."""
    args = parse_args()
    if args.command == "arms":
        add_arms(args)
    else:
        make_bins(args)


if __name__ == "__main__":
    main()
