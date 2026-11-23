#!/usr/bin/env bash
# Download one source file for building the workflow's KaryoScope database.
# Runs on the node Snakemake is started from (local rule, no container).
#
# Usage: karyoscope_fetch_source.sh TARGET URL SHA256
#   SHA256 may be empty (no check). On failure, prints how to download the
#   file elsewhere and where to put it, then exits 1.
set -euo pipefail

target=$1
url=$2
sha256=$3

mkdir -p "$(dirname "${target}")"
target_abs="$(cd "$(dirname "${target}")" && pwd)/$(basename "${target}")"
part="${target_abs}.part"

echo "[karyoscope_sources] downloading $(basename "${target}")"
if ! curl -fL --retry 2 --connect-timeout 30 -o "${part}" "${url}"; then
    rm -f "${part}"
    cat >&2 <<EOF

[karyoscope_sources] ERROR: could not download $(basename "${target}")
(no internet access from this machine?).

To build the KaryoScope database, the workflow needs this source file. Download
it on a machine with internet access:

    curl -L -o $(basename "${target}") "${url}"
EOF
    if [[ -n "${sha256}" ]]; then
        cat >&2 <<EOF
    echo "${sha256}  $(basename "${target}")" | sha256sum -c -
EOF
    fi
    cat >&2 <<EOF

then copy it to
    ${target_abs}
and start the workflow again. See docs/karyoscope/README.md, "Database".

EOF
    exit 1
fi

if [[ -n "${sha256}" ]]; then
    if ! echo "${sha256}  ${part}" | sha256sum -c - > /dev/null; then
        rm -f "${part}"
        echo "[karyoscope_sources] ERROR: checksum mismatch for $(basename "${target}")" >&2
        exit 1
    fi
fi
mv "${part}" "${target_abs}"
echo "[karyoscope_sources] $(basename "${target}") done"
