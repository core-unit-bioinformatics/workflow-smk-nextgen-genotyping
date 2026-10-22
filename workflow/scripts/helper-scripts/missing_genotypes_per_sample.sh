#!/usr/bin/env bash
#
# Per-sample count and fraction of missing genotypes (no-calls) in a (multi-sample) VCF.
#
# Usage:
#   ./missing_genotypes_per_sample.sh INPUT.vcf.gz OUTPUT.tsv
#
# Requires bcftools. Output columns: sample, n_missing, n_total, frac_missing
# (sorted by frac_missing, highest first).

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 INPUT.vcf.gz OUTPUT.tsv" >&2
    exit 1
fi

input="$1"
output="$2"

{
    printf 'sample\tn_missing\tn_total\tfrac_missing\n'
    bcftools stats -s - "$input" | awk -F'\t' '
        /^# PSC\t/ { for (i = 2; i <= NF; i++) { name = $i; sub(/^\[[0-9]+\]/, "", name); col[name] = i } next }
        /^PSC\t/   { total = 0
                     for (k in col) if (k ~ /^n(RefHom|NonRefHom|Hets|HapRef|HapAlt|Missing)$/) total += $col[k]
                     printf "%s\t%.0f\t%.0f\t%.6f\n", $col["sample"], $col["nMissing"], total, $col["nMissing"] / total }
    ' | sort -t"$(printf '\t')" -k4,4gr
} > "$output"
