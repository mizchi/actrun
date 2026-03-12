#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
  echo "usage: $0 <workflow-file> [repo] [ref]" >&2
  exit 1
fi

workflow_file="$1"
repo="${2:-mizchi/action_runner}"
ref="${3:-main}"
compat_key=""
dispatch_args=()

case "$workflow_file" in
  compat-cache-auto-save.yml)
    compat_key="compat-cache-auto-save-$(date +%s)-$$"
    dispatch_args=(-f "compat_key=$compat_key")
    ;;
esac

echo "dispatching $workflow_file on $repo@$ref"
if [ "${#dispatch_args[@]}" -gt 0 ]; then
  gh workflow run "$workflow_file" -R "$repo" --ref "$ref" "${dispatch_args[@]}"
else
  gh workflow run "$workflow_file" -R "$repo" --ref "$ref"
fi

run_id=""
for _ in $(seq 1 24); do
  run_id="$(
    gh run list \
      -R "$repo" \
      --workflow "$workflow_file" \
      --limit 10 \
      --json databaseId,headBranch,event,createdAt \
      --jq 'map(select(.event=="workflow_dispatch" and .headBranch=="'"$ref"'")) | sort_by(.createdAt) | last | .databaseId // empty'
  )"
  if [ -n "$run_id" ]; then
    break
  fi
  sleep 5
done

if [ -z "$run_id" ]; then
  echo "failed to locate dispatched run for $workflow_file" >&2
  exit 1
fi

run_url="$(
  gh run view "$run_id" -R "$repo" --json url --jq '.url'
)"

echo "watching run $run_id"
echo "$run_url"
gh run watch "$run_id" -R "$repo" --interval 5 --exit-status

download_dir="_build/gha-compat/$run_id"
rm -rf "$download_dir"
mkdir -p "$download_dir"
gh run download "$run_id" -R "$repo" --dir "$download_dir"

moon build src/main --target native >/dev/null
ACTION_RUNNER_COMPAT_CACHE_KEY="$compat_key" \
  bash scripts/gha_compat_compare.sh "$workflow_file" "$download_dir"
