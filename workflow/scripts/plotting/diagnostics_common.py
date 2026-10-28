"""Shared helpers for the PanGenie diagnostic plots (table loading, plot style, saving)."""  # noqa: E501

import dataclasses

import matplotlib.colors
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

CLASS_NAMES = ("snv", "indel", "sv", "other")
PLOT_CLASSES = ("all", "snv", "indel", "sv")

SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK_SECONDARY = "#52514e"
INK_MUTED = "#898781"
GRID = "#e1e0d9"
SERIES_BLUE = "#2a78d6"
# sequential single-hue ramp (light -> dark) used for density plots
SEQUENTIAL = matplotlib.colors.LinearSegmentedColormap.from_list(
    "blue_sequential",
    ["#cde2fb", "#86b6ef", "#3987e5", "#256abf", "#184f95", "#0d366b"],
)


@dataclasses.dataclass
class VariantTable:
    """Compact per-variant arrays; variants are identified by a 64-bit hash of their ID."""  # noqa: E501

    key: np.ndarray
    class_code: np.ndarray
    af: np.ndarray
    het: np.ndarray
    ns: np.ndarray

    def select(self, plot_class):
        """Return a boolean mask of the variants belonging to a plot class ('all', 'snv', ...)."""  # noqa: E501
        if plot_class == "all":
            return np.ones(len(self.key), dtype=bool)
        return self.class_code == CLASS_NAMES.index(plot_class)


def class_label(plot_class, sv_min_length):
    """Return the human-readable label of a plot class."""
    labels = {
        "all": "all variants",
        "snv": "SNVs",
        "indel": f"indels (1 to {sv_min_length - 1} bp)",
        "sv": f"SVs (>= {sv_min_length} bp)",
    }
    return labels[plot_class]


def load_variant_table(path, chunksize=2_000_000):
    """Read a variant table (.tsv.gz from variant_table.py) in chunks into compact numpy arrays."""  # noqa: E501
    keys, codes, afs, hets, nss = [], [], [], [], []
    reader = pd.read_csv(
        path,
        sep="\t",
        usecols=["id", "class", "af", "ns", "ac_het"],
        dtype={
            "id": str,
            "class": str,
            "af": "float32",
            "ns": "float32",
            "ac_het": "float32",
        },
        na_values=["NA"],
        chunksize=chunksize,
    )
    for chunk in reader:
        code = pd.Categorical(chunk["class"], categories=CLASS_NAMES).codes
        if (code < 0).any():
            raise ValueError(f"unknown variant class in {path}")
        ns = chunk["ns"].to_numpy()
        het = np.full(len(chunk), np.nan, dtype="float32")
        np.divide(chunk["ac_het"].to_numpy(), ns, out=het, where=ns > 0)
        keys.append(pd.util.hash_pandas_object(chunk["id"], index=False).to_numpy())
        codes.append(code.astype(np.uint8))
        afs.append(chunk["af"].to_numpy())
        hets.append(het)
        nss.append(ns)
    return VariantTable(
        key=np.concatenate(keys),
        class_code=np.concatenate(codes),
        af=np.concatenate(afs),
        het=np.concatenate(hets),
        ns=np.concatenate(nss),
    )


def apply_style():
    """Set the matplotlib defaults used by all diagnostic plots."""
    plt.rcParams.update(
        {
            "figure.facecolor": SURFACE,
            "axes.facecolor": SURFACE,
            "savefig.facecolor": SURFACE,
            "axes.edgecolor": INK_MUTED,
            "axes.labelcolor": INK_SECONDARY,
            "axes.titlecolor": INK,
            "axes.spines.top": False,
            "axes.spines.right": False,
            "axes.grid": True,
            "grid.color": GRID,
            "grid.linewidth": 0.6,
            "axes.axisbelow": True,
            "xtick.color": INK_MUTED,
            "ytick.color": INK_MUTED,
            "text.color": INK_SECONDARY,
            "font.size": 9,
            "axes.titlesize": 10,
            "pdf.fonttype": 42,
        }
    )


def draw_density(ax, x, y, bins=200):
    """Draw a log-scaled 2D histogram of x vs. y on the unit square; return the mappable (or None)."""  # noqa: E501
    counts, xedges, yedges = np.histogram2d(x, y, bins=bins, range=[[0, 1], [0, 1]])
    if counts.max() == 0:
        return None
    return ax.pcolormesh(
        xedges,
        yedges,
        np.ma.masked_equal(counts.T, 0),
        cmap=SEQUENTIAL,
        norm=matplotlib.colors.LogNorm(vmin=1, vmax=counts.max()),
        rasterized=True,
        linewidth=0,
    )


def write_note(ax, text):
    """Write a centered note into an (empty) axes."""
    ax.text(
        0.5,
        0.5,
        text,
        transform=ax.transAxes,
        ha="center",
        va="center",
        color=INK_SECONDARY,
    )


def save_figure(fig, prefix):
    """Save a figure as <prefix>.png and <prefix>.pdf and close it."""
    fig.savefig(f"{prefix}.png", dpi=200)
    fig.savefig(f"{prefix}.pdf")
    plt.close(fig)
