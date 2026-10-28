#!/usr/bin/env python3
"""HWE plots: fraction of heterozygous genotypes vs. allele frequency, one point per variant.

Writes <out-prefix>.<class>.png and <out-prefix>.<class>.pdf for the classes
all, snv, indel and sv. Variants are shown as a log-scaled density; the dashed
line is the expectation under Hardy-Weinberg equilibrium, 2p(1-p).
"""  # noqa: E501

import argparse

import diagnostics_common as common
import matplotlib.pyplot as plt
import numpy as np


def plot_one_class(table, variant_class, args):
    """Draw and save the HWE plot of one variant class."""
    selected = table.select(variant_class)
    valid = selected & ~np.isnan(table.af) & ~np.isnan(table.het)
    title = f"{common.class_label(variant_class, args.sv_min_length)}: n = {int(valid.sum()):,} genotyped variants"  # noqa: E501

    fig, ax = plt.subplots(figsize=(5.2, 4.4), layout="constrained")
    mappable = common.draw_density(ax, table.af[valid], table.het[valid])
    allele_freq = np.linspace(0, 1, 201)
    ax.plot(
        allele_freq,
        2 * allele_freq * (1 - allele_freq),
        color=common.INK_SECONDARY,
        linestyle="--",
        linewidth=1.2,
        label="expected under HWE: 2p(1-p)",
    )
    if mappable is None:
        common.write_note(ax, "no variants of this class")
    else:
        fig.colorbar(mappable, ax=ax, label="variants per bin", shrink=0.85)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.set_xlabel("Allele frequency in cohort")
    ax.set_ylabel("Fraction of heterozygous genotypes")
    ax.set_title(title, loc="left")
    ax.legend(loc="upper center", frameon=False)
    ax.grid(False)
    common.save_figure(fig, f"{args.out_prefix}.{variant_class}")


def main():
    """Load the cohort table once and write the plots of all classes."""
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--cohort-table", required=True, help="cohort variant table (.tsv.gz)"
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
    table = common.load_variant_table(args.cohort_table)
    for variant_class in common.PLOT_CLASSES:
        plot_one_class(table, variant_class, args)


if __name__ == "__main__":
    main()
