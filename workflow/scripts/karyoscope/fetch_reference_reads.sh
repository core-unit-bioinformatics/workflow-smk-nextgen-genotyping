#!/usr/bin/env bash
# Download a fixed number of read pairs of normal genomes from the 1000 Genomes
# 30x WGS data (NYGC, Illumina NovaSeq 2x150, ENA studies PRJEB31736 and
# PRJEB36890), for deriving KaryoScope reference values. Runs on a machine with
# internet, NOT part of the workflow.
#
# Only the first N read pairs of each sample's first run are streamed (FASTQ
# order follows the flowcell, not the genome, so this is a random subsample);
# nothing else is downloaded.
#
# Usage: fetch_reference_reads.sh OUTDIR [READ_PAIRS] [SAMPLE ...]
#   READ_PAIRS default 20000000 (~6 Gbp, ~2x coverage)
#   SAMPLE     default: 8 unrelated individuals, 4 female / 4 male,
#              4 populations (CEU, YRI, CHS, PUR)
# Writes OUTDIR/<sample>_R1.fq.gz, _R2.fq.gz and OUTDIR/sample_sheet_reference.tsv
set -euo pipefail

outdir=${1:?usage: fetch_reference_reads.sh OUTDIR [READ_PAIRS] [SAMPLE ...]}
pairs=${2:-20000000}
shift $(( $# >= 2 ? 2 : $# ))
samples=("$@")
if [[ ${#samples[@]} -eq 0 ]]; then
    # sample    sex  population
    # NA12891   M    CEU (Utah, European ancestry)
    # NA12892   F    CEU
    # NA19239   M    YRI (Yoruba, Nigeria)
    # NA19238   F    YRI
    # HG00512   M    CHS (Southern Han Chinese)
    # HG00513   F    CHS
    # HG00731   M    PUR (Puerto Rico)
    # HG00732   F    PUR
    samples=(NA12891 NA12892 NA19239 NA19238 HG00512 HG00513 HG00731 HG00732)
fi

mkdir -p "${outdir}"
outdir=$(cd "${outdir}" && pwd)
lines=$((pairs * 4))
api="https://www.ebi.ac.uk/ena/portal/api/search"
sheet="${outdir}/sample_sheet_reference.tsv"
printf 'sample\tinput_path\ttech\n' > "${sheet}"

for sample in "${samples[@]}"; do
    echo "[reference_reads] ${sample}: looking up the 30x run in ENA"
    query="(study_accession=\"PRJEB31736\" OR study_accession=\"PRJEB36890\") AND sample_alias=\"${sample}\""
    row=$(curl -fsS -G "${api}" \
        --data-urlencode "result=read_run" \
        --data-urlencode "query=${query}" \
        --data-urlencode "fields=run_accession,fastq_ftp" \
        --data-urlencode "format=tsv" | sed -n 2p)
    if [[ -z "${row}" ]]; then
        echo "[reference_reads] ERROR: no 30x run found for ${sample}" >&2
        exit 1
    fi
    run=$(cut -f1 <<< "${row}")
    ftp=$(cut -f2 <<< "${row}")
    r1=$(tr ';' '\n' <<< "${ftp}" | grep '_1.fastq.gz$')
    r2=$(tr ';' '\n' <<< "${ftp}" | grep '_2.fastq.gz$')
    echo "[reference_reads] ${sample}: run ${run}, first ${pairs} read pairs"
    for mate in 1 2; do
        url=$([[ ${mate} == 1 ]] && echo "${r1}" || echo "${r2}")
        target="${outdir}/${sample}_R${mate}.fq.gz"
        # head ends the download early; curl's broken-pipe exit is expected
        { curl -fsS "https://${url}" || true; } | { zcat 2> /dev/null || true; } \
            | head -n "${lines}" | gzip -c > "${target}"
        got=$(( $(zcat "${target}" | wc -l) / 4 ))
        if (( got < pairs )); then
            echo "[reference_reads] ERROR: ${target} has only ${got} reads" >&2
            exit 1
        fi
    done
    printf '%s\t%s,%s\tsr\n' "${sample}" \
        "${outdir}/${sample}_R1.fq.gz" "${outdir}/${sample}_R2.fq.gz" >> "${sheet}"
done

echo "[reference_reads] done: ${#samples[@]} samples in ${outdir}"
echo "[reference_reads] sample sheet: ${sheet} (adjust the paths after copying)"
