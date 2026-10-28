#!/usr/bin/env python3
"""Distribution of the number of SVs per sample (genotype 0/1 or 1/1).

Reads the table from sv_per_sample_table.py and writes <out-prefix>.png and
<out-prefix>.pdf with one histogram each for all SVs, deletions and insertions.
"""

import argparse

import diagnostics_common as common
import matplotlib.pyplot as plt
import matplotlib.ticker
import numpy as np
import pandas as pd

PANELS = (("all", "All SVs"), ("deletion", "Deletions"), ("insertion", "Insertions"))


def main():
    """Read the per-sample SV table and draw the three histograms."""
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--table", required=True, help="per-sample SV table (TSV)")
    parser.add_argument(
        "--out-prefix", required=True, help="output path prefix (without extension)"
    )
    parser.add_argument(
        "--sv-min-length",
        type=int,
        default=50,
        help="SV length threshold used for the title",
    )
    args = parser.parse_args()

    common.apply_style()
    table = pd.read_csv(args.table, sep="\t")
    n_samples = table["sample"].nunique()

    fig, axes = plt.subplots(1, len(PANELS), figsize=(10.5, 3.6), layout="constrained")
    for ax, (sv_class, title) in zip(axes, PANELS, strict=True):
        values = table.loc[table["sv_class"] == sv_class, "n_carried"].to_numpy()
        if len(values) == 0:
            common.write_note(ax, "no data")
            continue
        edges = np.histogram_bin_edges(values, bins="auto")
        ax.hist(
            values,
            bins=edges,
            color=common.SERIES_BLUE,
            edgecolor=common.SURFACE,
            linewidth=0.8,
        )
        median = float(np.median(values))
        ax.axvline(median, color=common.INK_SECONDARY, linestyle="--", linewidth=1.2)
        ax.text(
            0.97,
            0.95,
            f"median {median:,.0f}",
            transform=ax.transAxes,
            ha="right",
            va="top",
            color=common.INK_SECONDARY,
        )
        ax.set_title(title, loc="left")
        ax.set_xlabel("SVs per sample")
        ax.yaxis.set_major_locator(matplotlib.ticker.MaxNLocator(integer=True))
        ax.grid(axis="x", visible=False)
    axes[0].set_ylabel("Samples")
    fig.suptitle(
        f"Structural variants per sample (|REF - ALT length| >= {args.sv_min_length} bp, genotype 0/1 or 1/1; "  # noqa: E501
        f"{n_samples} samples)",
        x=0.01,
        ha="left",
        fontsize=10,
        color=common.INK,
    )
    common.save_figure(fig, args.out_prefix)


if __name__ == "__main__":
    main()
