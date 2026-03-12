#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <workflow-file> <downloaded-artifact-dir>" >&2
  exit 1
fi

workflow_file="$1"
download_dir="$2"
repo_root="$(pwd)"
repo_slug="mizchi/action_runner"
repo_name="action_runner"
local_root="$repo_root/_build/gha-compat/local/${workflow_file%.yml}"
workspace_root="$local_root/$repo_name/$repo_name"
workflow_src="$repo_root/.github/workflows/$workflow_file"
workflow_dst="$workspace_root/.github/workflows/$workflow_file"
event_path="$workspace_root/event.json"
cli_bin="$repo_root/_build/native/debug/build/main/main.exe"
event_added_path=".github/workflows/$workflow_file"
compat_key="${ACTION_RUNNER_COMPAT_CACHE_KEY:-}"
seed_license=0

case "$workflow_file" in
  compat-checkout-artifact.yml)
    report_name="compat-checkout-report"
    ;;
  compat-checkout-sparse.yml)
    report_name="compat-checkout-sparse-report"
    seed_license=1
    ;;
  compat-artifact-multi-job.yml)
    report_name="compat-artifact-report"
    ;;
  compat-cache-roundtrip.yml)
    report_name="compat-cache-report"
    ;;
  compat-cache-auto-save.yml)
    report_name="compat-cache-auto-save-report"
    event_added_path=".github/workflows/__compat_cache_auto_save__.trigger"
    if [ -z "$compat_key" ]; then
      compat_key="compat-cache-auto-save-local"
    fi
    ;;
  *)
    echo "unsupported compat workflow: $workflow_file" >&2
    exit 1
    ;;
esac

if [ ! -f "$workflow_src" ]; then
  echo "missing workflow source: $workflow_src" >&2
  exit 1
fi

if [ ! -d "$download_dir/$report_name" ]; then
  echo "missing downloaded artifact dir: $download_dir/$report_name" >&2
  exit 1
fi

rm -rf "$local_root"
mkdir -p "$(dirname "$workflow_dst")"
cp "$workflow_src" "$workflow_dst"
cp "$repo_root/README.md" "$workspace_root/README.md"
if [ "$seed_license" = "1" ]; then
  cp "$repo_root/LICENSE" "$workspace_root/LICENSE"
fi

if [ -n "$compat_key" ]; then
  placeholder='${{ inputs.compat_key }}'
  workflow_text="$(cat "$workflow_dst")"
  workflow_text="${workflow_text//$placeholder/$compat_key}"
  printf '%s' "$workflow_text" > "$workflow_dst"
fi

cat > "$event_path" <<EOF
{
  "ref": "refs/heads/main",
  "before": "1111111111111111111111111111111111111111",
  "after": "2222222222222222222222222222222222222222",
  "repository": {
    "full_name": "$repo_slug"
  },
  "sender": {
    "login": "compat-bot"
  },
  "commits": [
    {
      "added": [
        "$event_added_path"
      ],
      "modified": [],
      "removed": []
    }
  ]
}
EOF

if [ ! -x "$cli_bin" ]; then
  echo "missing built CLI: $cli_bin" >&2
  exit 1
fi

"$cli_bin" "$workflow_dst" --event "$event_path" >/dev/null

local_report="$workspace_root/report/result.txt"
remote_report="$download_dir/$report_name/result.txt"

if [ ! -f "$local_report" ]; then
  echo "missing local report: $local_report" >&2
  exit 1
fi

if [ ! -f "$remote_report" ]; then
  echo "missing downloaded report: $remote_report" >&2
  exit 1
fi

local_value="$(cat "$local_report")"
remote_value="$(cat "$remote_report")"

if [ "$local_value" != "$remote_value" ]; then
  echo "compat mismatch for $workflow_file" >&2
  echo "local : $local_value" >&2
  echo "remote: $remote_value" >&2
  exit 1
fi

echo "compat ok: $workflow_file"
