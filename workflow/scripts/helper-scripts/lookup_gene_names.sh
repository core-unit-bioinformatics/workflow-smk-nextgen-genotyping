#!/usr/bin/env bash
#
# Example usage:
# conda activate gene_lookup
# ./lookup_gene_names.sh HLA-A SMN1 SMN2
#
# Gene coordinate lookup via mygene.info (GRCh38),
# Only positions on primary chromosomes (1-22, X, Y) are reported; genes that
# exist only on alternate contigs are skipped with a note on stderr.
# Requires the 'gene_lookup' conda environment:
#   conda create -n gene_lookup -c conda-forge python=3.11 pandas pip
#   conda activate gene_lookup
#   pip install mygene
#

set -euo pipefail

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 GENE1 [GENE2 ...]" >&2
    exit 1
fi

python3 -c "
import mygene, sys
PRIMARY = {str(i) for i in range(1, 23)} | {'X', 'Y'}
mg = mygene.MyGeneInfo()
for symbol in sys.argv[1:]:
    hits = mg.query(f'symbol:{symbol}', species='human', fields='genomic_pos')['hits']
    if not hits or 'genomic_pos' not in hits[0]:
        print(f'# NOT FOUND: {symbol}', file=sys.stderr)
        continue
    positions = hits[0]['genomic_pos']
    if not isinstance(positions, list):
        positions = [positions]
    primary = [pos for pos in positions if str(pos['chr']) in PRIMARY]
    if not primary:
        contigs = ', '.join(str(pos['chr']) for pos in positions)
        print(f'# NO PRIMARY-CHROMOSOME POSITION: {symbol} (found only on: {contigs})', file=sys.stderr)
        continue
    pos = primary[0]
    print(f\"chr{pos['chr']}\t{pos['start']-1}\t{pos['end']}\t{symbol}\")
" "$@"