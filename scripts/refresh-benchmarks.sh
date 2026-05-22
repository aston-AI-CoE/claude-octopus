#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
BENCHMARK_DIR="$PLUGIN_DIR/data/benchmarks"
CSV_PATH="$BENCHMARK_DIR/bullshitbench-v2-leaderboard.csv"
MANIFEST_PATH="$BENCHMARK_DIR/bullshitbench-v2-manifest.json"

mkdir -p "$BENCHMARK_DIR"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat << EOF
Usage: $(basename "$0")

Refreshes the checked-in BullshitBench v2 snapshot metadata.
The leaderboard source currently publishes a browser viewer, so this script
validates the local CSV schema and stamps the manifest for review in git.
EOF
    exit 0
fi

if [[ ! -f "$CSV_PATH" ]]; then
    echo "Missing CSV snapshot: $CSV_PATH" >&2
    exit 1
fi

header="$(head -n 1 "$CSV_PATH")"
expected="provider,model,reasoning,clear_pushback_rate,accepted_nonsense_rate,source"
if [[ "$header" != "$expected" ]]; then
    echo "Unexpected benchmark CSV columns." >&2
    echo "Expected: $expected" >&2
    echo "Actual:   $header" >&2
    exit 1
fi

generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
jq --arg generated_at "$generated_at" '.snapshot_generated_at = $generated_at' "$MANIFEST_PATH" > "${MANIFEST_PATH}.tmp"
mv "${MANIFEST_PATH}.tmp" "$MANIFEST_PATH"

echo "Updated $MANIFEST_PATH"
