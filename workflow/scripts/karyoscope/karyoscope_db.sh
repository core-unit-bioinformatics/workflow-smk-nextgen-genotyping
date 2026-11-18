#!/usr/bin/env bash
# Make sure a KaryoScope database is installed and registered in DB_ROOT.
#
# Order of checks:
#   1. registered in DB_ROOT/installed.json          -> nothing to do
#   2. extracted folder DB_ROOT/DB_ID present        -> register it
#   3. tarball DB_ROOT/DB_ID.tar.gz present          -> verify, extract, register
#   4. nothing present                               -> karyoscope download
#   5. download fails                                -> error with instructions
#
# Usage: karyoscope_db.sh DB_ROOT DB_ID SHA256 URL MARKER
set -euo pipefail

db_root=$1
db_id=$2
sha256=$3
url=$4
marker=$5

mkdir -p "${db_root}"
db_root=$(cd "${db_root}" && pwd)   # absolute, for the messages
tarball="${db_root}/${db_id}.tar.gz"

is_registered() {
    python3 - "${db_root}" "${db_id}" <<'EOF'
import json
import pathlib
import sys

state = pathlib.Path(sys.argv[1], "installed.json")
if not state.is_file():
    sys.exit(1)
databases = json.loads(state.read_text(encoding="utf-8")).get("databases", {})
sys.exit(0 if sys.argv[2] in databases else 1)
EOF
}

if is_registered; then
    echo "[karyoscope_db] ${db_id} is already registered in ${db_root}"

elif [[ -f "${db_root}/${db_id}/manifest.yaml" ]]; then
    echo "[karyoscope_db] ${db_id} is extracted but not registered, registering"
    karyoscope register "${db_id}" --db-root "${db_root}"

elif [[ -f "${tarball}" ]]; then
    echo "[karyoscope_db] found ${tarball}"
    if [[ -n "${sha256}" ]]; then
        echo "[karyoscope_db] checking SHA-256"
        if ! echo "${sha256}  ${tarball}" | sha256sum -c -; then
            echo "[karyoscope_db] ERROR: checksum mismatch for ${tarball}" >&2
            echo "[karyoscope_db] incomplete or corrupt copy? Download/copy it again." >&2
            exit 1
        fi
    else
        echo "[karyoscope_db] WARNING: no SHA-256 configured, skipping the check"
    fi
    echo "[karyoscope_db] extracting (needs ~23 GB next to the tarball)"
    tar -C "${db_root}" -xzf "${tarball}"
    karyoscope register "${db_id}" --db-root "${db_root}"
    rm -f "${tarball}"

else
    echo "[karyoscope_db] ${db_id} not found in ${db_root}, trying to download it"
    if ! karyoscope download "${db_id}" --db-root "${db_root}" --quiet; then
        cat >&2 <<EOF

[karyoscope_db] ERROR: the KaryoScope database ${db_id} is not present in
    ${db_root}
and could not be downloaded (no internet access from this machine?).

Download it on a machine with internet access:

    curl -L -o ${db_id}.tar.gz "${url}"
    echo "${sha256}  ${db_id}.tar.gz" | sha256sum -c -

then copy ${db_id}.tar.gz into
    ${db_root}/
and start the workflow again. It will be verified, extracted and registered
automatically (~36 GB free space needed there during extraction).

EOF
        exit 1
    fi
fi

touch "${marker}"
echo "[karyoscope_db] ${db_id} ready"
