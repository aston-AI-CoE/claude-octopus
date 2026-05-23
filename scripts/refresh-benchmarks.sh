#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
BENCHMARK_DIR="$PLUGIN_DIR/data/benchmarks"
CSV_PATH="$BENCHMARK_DIR/bullshitbench-v2-leaderboard.csv"
MANIFEST_PATH="$BENCHMARK_DIR/bullshitbench-v2-manifest.json"
UPSTREAM_CSV_URL="https://raw.githubusercontent.com/petergpt/bullshit-benchmark/main/data/v2/latest/leaderboard_with_launch.csv"
UPSTREAM_MANIFEST_URL="https://raw.githubusercontent.com/petergpt/bullshit-benchmark/main/data/v2/latest/manifest.json"

mkdir -p "$BENCHMARK_DIR"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat << EOF
Usage: $(basename "$0")

Refreshes the checked-in BullshitBench v2 snapshot from upstream raw GitHub
sources, validates the normalized CSV schema, and leaves the diff for review.
EOF
    exit 0
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/octopus-benchmarks.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

raw_csv="$tmp_dir/leaderboard_with_launch.csv"
raw_manifest="$tmp_dir/manifest.json"

curl -fsSL "$UPSTREAM_CSV_URL" -o "$raw_csv"
curl -fsSL "$UPSTREAM_MANIFEST_URL" -o "$raw_manifest"

python3 - "$raw_csv" "$CSV_PATH" <<'PY'
import csv
import sys

raw_path, out_path = sys.argv[1:3]
required = {"provider", "model", "reasoning", "clear_pushback_rate", "accepted_nonsense_rate"}
with open(raw_path, newline="") as fh:
    reader = csv.DictReader(fh)
    if not reader.fieldnames:
        raise SystemExit("upstream leaderboard has no header")
    missing = required - set(reader.fieldnames)
    if missing:
        raise SystemExit(f"upstream leaderboard missing columns: {', '.join(sorted(missing))}")
    rows = list(reader)

with open(out_path, "w", newline="") as fh:
    writer = csv.DictWriter(
        fh,
        fieldnames=[
            "provider",
            "model",
            "reasoning",
            "clear_pushback_rate",
            "accepted_nonsense_rate",
            "source",
        ],
    )
    writer.writeheader()
    for row in rows:
        writer.writerow(
            {
                "provider": row["provider"],
                "model": row["model"],
                "reasoning": row["reasoning"],
                "clear_pushback_rate": row["clear_pushback_rate"],
                "accepted_nonsense_rate": row["accepted_nonsense_rate"],
                "source": "bullshitbench-v2",
            }
        )
PY

header="$(head -n 1 "$CSV_PATH")"
expected="provider,model,reasoning,clear_pushback_rate,accepted_nonsense_rate,source"
if [[ "$header" != "$expected" ]]; then
    echo "Unexpected benchmark CSV columns." >&2
    echo "Expected: $expected" >&2
    echo "Actual:   $header" >&2
    exit 1
fi

generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
jq \
    --arg generated_at "$generated_at" \
    --arg source_url "$UPSTREAM_CSV_URL" \
    --arg manifest_url "$UPSTREAM_MANIFEST_URL" \
    '.snapshot_generated_at = $generated_at
     | .source_url = $source_url
     | .manifest_url = $manifest_url' \
    "$MANIFEST_PATH" > "${MANIFEST_PATH}.tmp"
mv "${MANIFEST_PATH}.tmp" "$MANIFEST_PATH"

echo "Updated $CSV_PATH"
echo "Updated $MANIFEST_PATH"
