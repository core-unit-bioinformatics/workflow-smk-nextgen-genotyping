#!/usr/bin/env python3
"""AF scatter plots: allele frequency in the genotyped cohort vs. in the reference panel.

Cohort and panel variants are joined by variant ID. Writes
<out-prefix>.<class>.png and <out-prefix>.<class>.pdf for the classes
all, snv, indel and sv. Variants are shown as a log-scaled density; the dashed
line is the diagonal (identical frequencies).
"""  # noqa: E501

import argparse
import sys

import diagnostics_common as common
import matplotlib.pyplot as plt
import numpy as np


def panel_af_for_cohort(cohort, panel):
    """Return the panel AF for every cohort variant (NaN if the ID is not in the panel)."""  # noqa: E501
    order = np.argsort(panel.key, kind="stable")
    panel_keys = panel.key[order]
    panel_af = panel.af[order]
    n_duplicated = len(panel_keys) - len(np.unique(panel_keys))
    if n_duplicated:
        print(
            f"WARNING: {n_duplicated} duplicated variant IDs in the panel table (first one used)",  # noqa: E501
            file=sys.stderr,
        )
    index = np.minimum(np.searchsorted(panel_keys, cohort.key), len(panel_keys) - 1)
    matched = panel_keys[index] == cohort.key
    return np.where(matched, panel_af[index], np.nan).astype("float32")


def plot_one_class(cohort, panel_af, variant_class, args):
    """Draw and save the AF scatter (density) plot of one variant class."""
    selected = cohort.select(variant_class)
    valid = selected & ~np.isnan(cohort.af) & ~np.isnan(panel_af)
    n_selected = int(selected.sum())
    n_valid = int(valid.sum())
    label = common.class_label(variant_class, args.sv_min_length)

    fig, ax = plt.subplots(figsize=(5.2, 4.4), layout="constrained")
    mappable = common.draw_density(ax, panel_af[valid], cohort.af[valid])
    ax.plot([0, 1], [0, 1], color=common.INK_SECONDARY, linestyle="--", linewidth=1.2)
    if mappable is None:
        common.write_note(ax, "no variants of this class")
    else:
        fig.colorbar(mappable, ax=ax, label="variants per bin", shrink=0.85)
    if n_valid > 1:
        r = np.corrcoef(
            panel_af[valid].astype("float64"), cohort.af[valid].astype("float64")
        )[0, 1]
        ax.text(
            0.04,
            0.96,
            f"Pearson r = {r:.3f}",
            transform=ax.transAxes,
            ha="left",
            va="top",
        )
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.set_xlabel("Allele frequency in reference panel")
    ax.set_ylabel("Allele frequency in cohort")
    ax.set_title(
        f"{label}: n = {n_valid:,} of {n_selected:,} cohort variants", loc="left"
    )
    ax.grid(False)
    common.save_figure(fig, f"{args.out_prefix}.{variant_class}")


def main():
    """Load both tables once, join them and write the plots of all classes."""
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--cohort-table", required=True, help="cohort variant table (.tsv.gz)"
    )
    parser.add_argument(
        "--panel-table", required=True, help="panel variant table (.tsv.gz)"
    )
    parser.add_argument(
        "--out-prefix",
        required=True,
        help="output path prefix (without class and extension)",
    )
    parser.add_argument(
        "--sv-min-length",
        type=int,
        default=50,
        help="SV length threshold used for the labels",
    )
    args = parser.parse_args()

    common.apply_style()
    cohort = common.load_variant_table(args.cohort_table)
    panel = common.load_variant_table(args.panel_table)
    panel_af = panel_af_for_cohort(cohort, panel)
    n_unmatched = int(np.isnan(panel_af).sum())
    print(
        f"{len(cohort.key)} cohort variants, {n_unmatched} without a panel match",
        file=sys.stderr,
    )
    for variant_class in common.PLOT_CLASSES:
        plot_one_class(cohort, panel_af, variant_class, args)


if __name__ == "__main__":
    main()
