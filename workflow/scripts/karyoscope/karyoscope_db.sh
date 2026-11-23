#!/usr/bin/env bash
# Register a KaryoScope database that is already present in DB_ROOT and check
# that it holds the requested feature sets.
#
#   1. registered in DB_ROOT/installed.json   -> nothing to register
#   2. folder DB_ROOT/DB_ID present             -> register it
#   3. tarball DB_ROOT/DB_ID.tar.gz present     -> (verify,) extract, register
#   then: every requested feature set must be in the database's manifest
#
# A database that is not present at all is built by the workflow instead
# (rules fetch_karyoscope_source / build_karyoscope_database).
#
# Usage: karyoscope_db.sh DB_ROOT DB_ID SHA256 FEATURE_SETS MARKER
#   SHA256 may be empty; FEATURE_SETS is comma-separated.
set -euo pipefail

db_root=$1
db_id=$2
sha256=$3
feature_sets=$4
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
    echo "[karyoscope_db] ${db_id} is present but not registered, registering"
    karyoscope register "${db_id}" --db-root "${db_root}"

elif [[ -f "${tarball}" ]]; then
    echo "[karyoscope_db] found ${tarball}"
    if [[ -n "${sha256}" ]]; then
        echo "[karyoscope_db] checking SHA-256"
        if ! echo "${sha256}  ${tarball}" | sha256sum -c -; then
            echo "[karyoscope_db] ERROR: checksum mismatch for ${tarball}" >&2
            echo "[karyoscope_db] incomplete or corrupt copy? Copy it again." >&2
            exit 1
        fi
    else
        echo "[karyoscope_db] no SHA-256 configured, skipping the check"
    fi
    echo "[karyoscope_db] extracting"
    tar -C "${db_root}" -xzf "${tarball}"
    karyoscope register "${db_id}" --db-root "${db_root}"
    rm -f "${tarball}"

else
    echo "[karyoscope_db] ERROR: ${db_id} not found in ${db_root}" >&2
    echo "[karyoscope_db] (the workflow decides at startup whether to build it;" >&2
    echo "[karyoscope_db]  restart Snakemake so it can schedule the build)" >&2
    exit 1
fi

echo "[karyoscope_db] checking feature sets: ${feature_sets}"
python3 - "${db_root}/${db_id}/manifest.yaml" "${feature_sets}" <<'EOF'
import pathlib
import sys

import yaml

manifest = yaml.safe_load(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
available = manifest.get("feature_sets", [])
missing = [fs for fs in sys.argv[2].split(",") if fs and fs not in available]
if missing:
    sys.exit(
        f"[karyoscope_db] ERROR: feature set(s) {missing} are not in this database.\n"
        f"[karyoscope_db] available: {', '.join(available)}\n"
        "[karyoscope_db] remove them from karyo-features / karyoscope.default_features"
    )
EOF

touch "${marker}"
echo "[karyoscope_db] ${db_id} ready"
