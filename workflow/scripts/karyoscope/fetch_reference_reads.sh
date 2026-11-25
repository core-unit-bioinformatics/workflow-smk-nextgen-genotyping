#!/usr/bin/env bash
# Download a random subsample of read pairs of normal genomes from the 1000
# Genomes 30x WGS data (NYGC, Illumina NovaSeq 2x150), for deriving KaryoScope
# reference values. Runs on a machine with internet, NOT part of the workflow.
#
# The 30x data were submitted to ENA as position-sorted CRAMs; ENA's FASTQs
# are generated from them and keep that order. So the first N reads would all
# come from chr1: instead, each FASTQ is streamed completely (~13 GB per mate)
# and a random fraction is kept with 'seqtk sample' (same seed for R1 and R2,
# so the pairs stay together). Only the subsample is written to disk.
#
# Usage: fetch_reference_reads.sh OUTDIR [READ_PAIRS] [SAMPLE ...]
#   READ_PAIRS default 20000000 (~6 Gbp, ~2x coverage; the result is within
#              a fraction of a percent of it)
#   SAMPLE     default: 8 unrelated individuals, 4 female / 4 male,
#              4 populations (CEU, YRI, CHS, PUR)
# Writes OUTDIR/<sample>_R1.fq.gz, _R2.fq.gz and OUTDIR/sample_sheet_reference.tsv
# Needs: curl, seqtk, gzip.
#
# Protocol for the downloads (default https): ENA_PROTOCOL=http|ftp bash ...
# Each file is tried up to 3 times (a broken stream starts again from scratch).
set -euo pipefail

protocol=${ENA_PROTOCOL:-https}
seed=11

outdir=${1:?usage: fetch_reference_reads.sh OUTDIR [READ_PAIRS] [SAMPLE ...]}
pairs=${2:-20000000}
shift $(( $# >= 2 ? 2 : $# ))
samples=("$@")
if [[ ${#samples[@]} -eq 0 ]]; then
    # sample    sex  population
    # NA12891   M    CEU (Utah, European ancestry)
    # NA12892   F    CEU
    # NA18486   M    YRI (Yoruba, Nigeria)
    # NA19238   F    YRI
    # HG00512   M    CHS (Southern Han Chinese)
    # HG00513   F    CHS
    # HG00731   M    PUR (Puerto Rico)
    # HG00732   F    PUR
    samples=(NA12891 NA12892 NA18486 NA19238 HG00512 HG00513 HG00731 HG00732)
fi

command -v seqtk > /dev/null || {
    echo "[reference_reads] ERROR: seqtk not found (e.g. conda install -c bioconda seqtk)" >&2
    exit 1
}

mkdir -p "${outdir}"
outdir=$(cd "${outdir}" && pwd)
api="https://www.ebi.ac.uk/ena/portal/api"
sheet="${outdir}/sample_sheet_reference.tsv"
printf 'sample\tinput_path\ttech\n' > "${sheet}"

# 1000 Genomes index files of the 30x data (sample name -> ENA run; the files
# listed there are the CRAMs) and the pedigree file (sex, population)
kg=ftp.1000genomes.ebi.ac.uk/vol1/ftp/data_collections/1000G_2504_high_coverage
index_files=(
    "${kg}/1000G_2504_high_coverage.sequence.index"
    "${kg}/1000G_698_related_high_coverage.sequence.index"
    "${kg}/20130606_g1k_3202_samples_ped_population.txt"
)
index_dir="${outdir}/.index"
mkdir -p "${index_dir}"
for index in "${index_files[@]}"; do
    local_index="${index_dir}/$(basename "${index}")"
    if [[ ! -s "${local_index}" ]]; then
        curl -fsS --connect-timeout 60 -o "${local_index}" "${protocol}://${index}" \
            || { echo "[reference_reads] could not get ${index}" >&2; rm -f "${local_index}"; }
    fi
done

lookup_run() {
    # print the ENA run accession of sample $1 from the index files
    # (awk reads the files itself: an early exit in a pipe would end the
    # script through SIGPIPE + pipefail)
    awk -F'\t' -v s="$1" '
        /^##/ { next }
        /^#/ { sub(/^#/, ""); delete col; for (i = 1; i <= NF; i++) col[$i] = i; next }
        ("SAMPLE_NAME" in col) && $col["SAMPLE_NAME"] == s { print $col["RUN_ID"]; exit }
    ' "${index_dir}"/*.sequence.index 2> /dev/null || true
}

sample_info() {
    # print "sex population" of sample $1 from the 1000 Genomes pedigree file
    awk -v s="$1" 'NR > 1 && $2 == s {
        print ($5 == 1 ? "male" : $5 == 2 ? "female" : "sex unknown"), $6; exit
    }' "${index_dir}/20130606_g1k_3202_samples_ped_population.txt" 2> /dev/null
}

count_reads() {
    if [[ -s "$1" ]]; then echo $(( $(zcat "$1" 2> /dev/null | wc -l) / 4 )); else echo 0; fi
}

for sample in "${samples[@]}"; do
    r1_out="${outdir}/${sample}_R1.fq.gz"
    r2_out="${outdir}/${sample}_R2.fq.gz"
    done_marker="${outdir}/.${sample}.subsampled"
    if [[ -f "${done_marker}" && -s "${r1_out}" && -s "${r2_out}" ]]; then
        echo "[reference_reads] ${sample}: already there, skipped"
        printf '%s\t%s,%s\tsr\n' "${sample}" "${r1_out}" "${r2_out}" >> "${sheet}"
        continue
    fi

    echo "[reference_reads] ${sample}: $(sample_info "${sample}")"
    run=$(lookup_run "${sample}")
    if [[ -z "${run}" ]]; then
        echo "[reference_reads] ERROR: ${sample} is not in the 1000 Genomes 30x index files." >&2
        echo "[reference_reads] Choose another sample, or rerun with the remaining ones." >&2
        exit 1
    fi
    # pick the columns by name (ENA adds run_accession as first column)
    echo "[reference_reads] ${sample}: run ${run}, asking ENA for the FASTQs"
    report=$(curl -fsS --connect-timeout 30 --max-time 120 --retry 3 --retry-delay 10 \
        "${api}/filereport?accession=${run}&result=read_run&fields=run_accession,fastq_ftp,read_count&format=tsv" \
        || true)
    ftp=$(awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) c[$i] = i; next }
        NR == 2 { print $c["fastq_ftp"] }' <<< "${report}")
    total=$(awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) c[$i] = i; next }
        NR == 2 { print $c["read_count"] }' <<< "${report}")
    r1=$(tr ';' '\n' <<< "${ftp}" | grep '_1.fastq.gz$' || true)
    r2=$(tr ';' '\n' <<< "${ftp}" | grep '_2.fastq.gz$' || true)
    if [[ -z "${r1}" || -z "${r2}" || -z "${total}" ]]; then
        echo "[reference_reads] ERROR: ENA has no paired FASTQs for ${sample} (run ${run}):" >&2
        echo "${report}" >&2
        exit 1
    fi
    fraction=$(awk -v n="${pairs}" -v t="${total}" 'BEGIN { printf "%.6f", n / t }')
    echo "[reference_reads] ${sample}: run ${run}, ${total} read pairs, keeping a random ${fraction}"

    rm -f "${done_marker}"
    for mate in 1 2; do
        url=$([[ ${mate} == 1 ]] && echo "${r1}" || echo "${r2}")
        target=$([[ ${mate} == 1 ]] && echo "${r1_out}" || echo "${r2_out}")
        # a finished mate file (only renamed from .part when complete) is kept:
        # same seed, same fraction, same input -> the same reads as a new run
        if [[ -s "${target}" ]]; then
            echo "[reference_reads]   $(basename "${target}") already complete, kept"
            continue
        fi
        ok=0
        for attempt in 1 2 3; do
            echo "[reference_reads]   ${protocol}://${url} (attempt ${attempt}, whole file is streamed)"
            if curl -fsS --connect-timeout 60 "${protocol}://${url}" \
                | seqtk sample -s "${seed}" - "${fraction}" | gzip -c > "${target}.part"; then
                mv "${target}.part" "${target}"
                ok=1
                break
            fi
            echo "[reference_reads]   download interrupted, retrying in 30 s" >&2
            sleep 30
        done
        if (( ! ok )); then
            rm -f "${target}.part"
            echo "[reference_reads] ERROR: could not download ${url}" >&2
            echo "[reference_reads] try another protocol: ENA_PROTOCOL=http or ftp" >&2
            exit 1
        fi
    done

    n1=$(count_reads "${r1_out}")
    n2=$(count_reads "${r2_out}")
    if (( n1 != n2 || n1 < pairs * 9 / 10 )); then
        echo "[reference_reads] ERROR: ${sample}: R1 ${n1} / R2 ${n2} reads (expected ~${pairs}, equal)" >&2
        exit 1
    fi
    touch "${done_marker}"
    echo "[reference_reads] ${sample}: ${n1} read pairs"
    printf '%s\t%s,%s\tsr\n' "${sample}" "${r1_out}" "${r2_out}" >> "${sheet}"
done

echo "[reference_reads] done: ${#samples[@]} samples in ${outdir}"
echo "[reference_reads] sample sheet: ${sheet} (adjust the paths after copying)"