#!/usr/bin/env bash
# Build and register the workflow's KaryoScope database from T2T-CHM13v2.0.
#
# Feature sets:
#   chromosome  one label per chromosome (karyoscope recipe)
#   region      p_arm / q_arm and centromeric satellites (karyoscope recipe)
#   gene        exon / intron / intergenic, RefSeq (karyoscope recipe)
#   cytoband    cytogenetic bands, hierarchy band -> band group -> arm -> chromosome
#   bins_<N>mb  fixed-size bins, labels chr1_0_1000000, ...
#
# Runs inside the KaryoScope container (karyoscope, hks, samtools, bgzip) and
# needs ~80 GB RAM at k=31 (or set MEM_GIGAS low and EXTERNAL_MEMORY to a dir).
#
# Usage: karyoscope_build_db.sh SRC_DIR DB_ROOT DB_ID BIN_SIZE_MB THREADS MEM_GIGAS \
#            FEATURE_BEDS_SCRIPT MARKER [EXTERNAL_MEMORY_DIR]
set -euo pipefail

src_dir=$1
db_root=$2
db_id=$3
bin_size_mb=$4
threads=$5
mem_gigas=$6
feature_beds=$7
marker=$8
external_memory=${9:-}

# recipe files shipped with KaryoScope (in the container)
recipe=/opt/KaryoScope/docs/recipes/files
fasta_content_sha256=15a4ba1246f6021a89699bf5083da7f2bad3f79c86acd7bc1eb0ca3a13164e85
bins_name="bins_${bin_size_mb}mb"
bin_size_bp=$((bin_size_mb * 1000000))

# everything absolute: the script works inside a build directory below
abspath() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }
mkdir -p "${db_root}"
db_root=$(cd "${db_root}" && pwd)
src_dir=$(cd "${src_dir}" && pwd)
feature_beds=$(abspath "${feature_beds}")
mkdir -p "$(dirname "${marker}")"
marker=$(abspath "${marker}")
if [[ -n "${external_memory}" ]]; then
    mkdir -p "${external_memory}"
    external_memory=$(cd "${external_memory}" && pwd)
fi
work="${db_root}/${db_id}.build"
rm -rf "${work}"
mkdir -p "${work}"
cd "${work}"

log() { echo "[karyoscope_build] $(date '+%F %T') $*"; }

log "genome: recompress with bgzip and index"
zcat "${src_dir}/chm13v2.0.fa.gz" | bgzip -@ "${threads}" > CHM13.fasta.gz
samtools faidx CHM13.fasta.gz
content=$(zcat CHM13.fasta.gz | sha256sum | cut -d' ' -f1)
if [[ "${content}" != "${fasta_content_sha256}" ]]; then
    echo "[karyoscope_build] ERROR: CHM13 FASTA content checksum mismatch" >&2
    echo "  expected ${fasta_content_sha256}" >&2
    echo "  got      ${content}" >&2
    echo "  incomplete download? Delete ${src_dir}/chm13v2.0.fa.gz and fetch it again." >&2
    exit 1
fi

log "chromosome"
karyoscope prep-bed fai --lengths CHM13.fasta.gz.fai --output chromosome.bed --force
cp "${recipe}/chm13v2_chromosome.hierarchy.txt" chromosome.hierarchy.txt

log "region"
karyoscope prep-bed censat --input "${src_dir}/chm13v2.0.cenSatv2.1.bed" \
    --lengths CHM13.fasta.gz.fai --output region.bed --hierarchy region.tsv \
    --priority region.priority.txt --force

log "gene"
cp "${recipe}/chm13v2_refseq_to_chr.tsv" refseq_to_chr.tsv
cp "${recipe}/chm13v2_gene.priority.txt" gene.priority.txt
karyoscope prep-bed gff-gene --input "${src_dir}/CHM13.gtf.gz" \
    --lengths CHM13.fasta.gz.fai --seqid-map refseq_to_chr.tsv \
    --output gene.bed --hierarchy gene.tsv --colors gene.colors.tsv --force

log "cytoband (with arm level)"
karyoscope prep-bed cytoband --input "${src_dir}/chm13v2.0_cytobands_allchrs.bed" \
    --lengths CHM13.fasta.gz.fai --output cytoband.bed --hierarchy cytoband.tsv \
    --colors cytoband.colors.tsv --force
python3 "${feature_beds}" arms --hierarchy cytoband.tsv --colors cytoband.colors.tsv

log "${bins_name}"
python3 "${feature_beds}" bins --fai CHM13.fasta.gz.fai --bin-size "${bin_size_bp}" \
    --output bins.bed --hierarchy bins.tsv

log "build spec"
external_line=""
if [[ -n "${external_memory}" ]]; then
    external_line=", external_memory: ${external_memory}"
fi
cat > build.yaml <<EOF
id: ${db_id}
version: "1.0.0"
sequence: CHM13.fasta.gz
kmer: { s: 31 }
build: { threads: ${threads}, mem_gigas: ${mem_gigas}${external_line} }
exclude: [chrM]
feature_sets:
  - name: chromosome
    bed: chromosome.bed
    hierarchy: chromosome.hierarchy.txt
    background: null
  - name: region
    bed: region.bed
    hierarchy: region.tsv
    priority: region.priority.txt
    background: null
  - name: gene
    bed: gene.bed
    hierarchy: gene.tsv
    priority: gene.priority.txt
    colors: gene.colors.tsv
    background: null
  - name: cytoband
    bed: cytoband.bed
    hierarchy: cytoband.tsv
    colors: cytoband.colors.tsv
    background: null
  - name: ${bins_name}
    bed: bins.bed
    hierarchy: bins.tsv
    background: null
roles:
  chromosome_assignment: chromosome
  region_assignment: region
  centromere_detection: region
smoothing:
  recommended_window_bp: 1000
EOF

log "karyoscope build (this is the long, memory-hungry part)"
karyoscope build --spec build.yaml --db-root "${db_root}" --force

# keep the small inputs for reproducibility, drop the big intermediates
keep="${db_root}/${db_id}/build_inputs"
mkdir -p "${keep}"
cp build.yaml ./*.tsv ./*.txt "${keep}/"
cd "${db_root}"
rm -rf "${work}"

touch "${marker}"
log "${db_id} built and registered in ${db_root}"
