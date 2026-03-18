#!/usr/bin/env bash
set -euo pipefail

# Compare GHA example snapshots (downloaded artifacts) with local golden files.
# Usage: bash scripts/snapshot_examples_compare.sh <downloaded-dir>
#   downloaded-dir: path to downloaded 'example-snapshots' artifact

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <downloaded-snapshots-dir>" >&2
  echo "  Download first: gh run download <run-id> -n example-snapshots -D <dir>" >&2
  exit 1
fi

DOWNLOADED_DIR="$1"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_DIR="$REPO_ROOT/testdata/snapshots/examples"

if [ ! -d "$DOWNLOADED_DIR" ]; then
  echo "error: directory not found: $DOWNLOADED_DIR"
  exit 1
fi

if [ ! -d "$LOCAL_DIR" ]; then
  echo "error: no local snapshots found. Run 'just snapshot-examples-update' first"
  exit 1
fi

pass=0
fail=0
skip=0

for remote_file in "$DOWNLOADED_DIR"/*.txt; do
  [ -f "$remote_file" ] || continue
  slug="$(basename "${remote_file%.txt}")"
  local_file="$LOCAL_DIR/$slug.txt"

  if [ ! -f "$local_file" ]; then
    echo "SKIP $slug (no local snapshot)"
    skip=$((skip + 1))
    continue
  fi

  echo -n "COMPARE $slug... "

  remote="$(cat "$remote_file")"
  local_val="$(cat "$local_file")"

  if [ "$remote" = "$local_val" ]; then
    echo "ok"
    pass=$((pass + 1))
  else
    echo "MISMATCH"
    echo "  local:  $(head -1 "$local_file")"
    echo "  remote: $(head -1 "$remote_file")"
    diff --color=auto "$local_file" "$remote_file" || true
    fail=$((fail + 1))
  fi
done

echo ""
echo "Compare: $pass passed, $fail failed, $skip skipped"

[ "$fail" -eq 0 ]
