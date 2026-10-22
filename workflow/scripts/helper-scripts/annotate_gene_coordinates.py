#!/usr/bin/env python3
"""
Look up genomic start/end coordinates (GRCh38, via mygene.info) for
each unique GeneSymbol in a ClinVar-style variant CSV, and:

  1. Write an annotated copy of the CSV with GeneStart/GeneEnd columns
     inserted right after PositionVCF.
  2. Write a deduplicated BED file (chrom, start, end, name) 

Requeries mygene.info

Usage:
    python3 annotate_gene_coordinates.py variants.csv \
        --out-csv variants.annotated.csv --out-bed genes.bed
"""

import argparse
import sys
import mygene
import pandas as pd


def fetch_gene_coordinates(gene_symbols):
    """Query mygene.info for GRCh38 genomic coordinates for a list of
    gene symbols. """
    mg = mygene.MyGeneInfo()
    results = mg.querymany(
        gene_symbols,
        scopes="symbol",
        species="human",
        fields="symbol,genomic_pos",
        as_dataframe=False,
    )

    by_query = {}
    for hit in results:
        by_query.setdefault(hit["query"], []).append(hit)

    coords = {}
    not_found = []
    ambiguous = []

    for symbol in gene_symbols:
        hits = by_query.get(symbol, [])
        hits = [h for h in hits if not h.get("notfound") and "genomic_pos" in h]

        if not hits:
            not_found.append(symbol)
            coords[symbol] = None
            continue

        if len(hits) > 1:
            ambiguous.append(symbol)

        pos = hits[0]["genomic_pos"]
        # genomic_pos can occasionally be a list (e.g. alt scaffolds) -
        # take the first entry, which is normally the primary assembly
        if isinstance(pos, list):
            pos = pos[0]

        coords[symbol] = (f"chr{pos['chr']}", int(pos["start"]), int(pos["end"]))

    if not_found:
        print(
            f"WARNING: {len(not_found)} gene symbol(s) not found, "
            f"GeneStart/GeneEnd will be blank for these: {sorted(not_found)}",
            file=sys.stderr,
        )
    if ambiguous:
        print(
            f"WARNING: {len(ambiguous)} gene symbol(s) had multiple hits, "
            f"used the first result for each: {sorted(ambiguous)}",
            file=sys.stderr,
        )

    return coords


def chrom_sort_key(chrom):
    """Natural sort key for chromosome names"""
    c = chrom.replace("chr", "")
    if c.isdigit():
        return (0, int(c), "")
    special_order = {"X": 1, "Y": 2, "M": 3, "MT": 3}
    if c in special_order:
        return (1, special_order[c], "")
    return (2, 0, c)


def check_chromosome_consistency(df, coords):
    """Optional sanity check: flag rows where the CSV's own Chromosome
    column disagrees with the chromosome mygene.info."""
    if "Chromosome" not in df.columns:
        return

    mismatches = []
    for _, row in df.iterrows():
        gene = row["GeneSymbol"]
        c = coords.get(gene)
        if c is None:
            continue
        csv_chrom = str(row["Chromosome"]).replace("chr", "")
        gene_chrom = c[0].replace("chr", "")
        if csv_chrom != gene_chrom:
            mismatches.append((gene, csv_chrom, gene_chrom))

    if mismatches:
        unique_mismatches = sorted(set(mismatches))
        print(
            f"WARNING: {len(unique_mismatches)} gene(s) have a chromosome "
            "mismatch between the CSV and mygene.info - please double-check "
            f"these: {unique_mismatches}",
            file=sys.stderr,
        )


def main():
    parser = argparse.ArgumentParser(
        description="Annotate a variant CSV with gene coordinates and produce a BED file."
    )
    parser.add_argument("csv", help="Input CSV (must contain 'GeneSymbol' and 'PositionVCF' columns)")
    parser.add_argument("--out-csv", required=True, help="Path to write the annotated CSV")
    parser.add_argument("--out-bed", required=True, help="Path to write the deduplicated BED file")
    args = parser.parse_args()

    df = pd.read_csv(args.csv, dtype=str)

    if "GeneSymbol" not in df.columns or "PositionVCF" not in df.columns:
        sys.exit("Error: input CSV must contain 'GeneSymbol' and 'PositionVCF' columns.")

    gene_symbols = sorted(df["GeneSymbol"].dropna().unique())
    print(f"Looking up coordinates for {len(gene_symbols)} unique gene symbol(s)...")
    coords = fetch_gene_coordinates(gene_symbols)

    check_chromosome_consistency(df, coords)

    df["GeneStart"] = df["GeneSymbol"].map(lambda g: coords[g][1] if coords.get(g) else float("nan"))
    df["GeneEnd"] = df["GeneSymbol"].map(lambda g: coords[g][2] if coords.get(g) else float("nan"))

    # move GeneStart/GeneEnd to sit right after PositionVCF
    cols = list(df.columns)
    cols.remove("GeneStart")
    cols.remove("GeneEnd")
    pos_idx = cols.index("PositionVCF")
    cols = cols[: pos_idx + 1] + ["GeneStart", "GeneEnd"] + cols[pos_idx + 1 :]
    df = df[cols]

    df.to_csv(args.out_csv, index=False)
    print(f"Annotated CSV written to: {args.out_csv}")

    # deduplicated BED: one row per unique gene with known coordinates
    bed_rows = []
    seen = set()
    for symbol in gene_symbols:
        if symbol in seen:
            continue
        seen.add(symbol)
        c = coords.get(symbol)
        if c is None:
            continue
        chrom, start, end = c
        bed_rows.append((chrom, start - 1, end, symbol))  # BED start is 0-based

    bed_rows.sort(key=lambda r: (chrom_sort_key(r[0]), r[1], r[2]))

    with open(args.out_bed, "w") as out:
        for chrom, start, end, name in bed_rows:
            out.write(f"{chrom}\t{start}\t{end}\t{name}\n")
    print(f"BED file written to: {args.out_bed} ({len(bed_rows)} unique loci)")


if __name__ == "__main__":
    main()