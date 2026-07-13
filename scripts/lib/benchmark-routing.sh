#!/usr/bin/env bash
# Council benchmark routing helpers.
# Source-safe: defines functions only.

council_snapshot_age_days() {
    local snapshot="$1"
    local now_epoch snapshot_epoch

    now_epoch="$(date -u +%s)"
    snapshot_epoch="$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$snapshot" +%s 2>/dev/null || date -u -d "$snapshot" +%s 2>/dev/null || echo "$now_epoch")"

    echo $(( (now_epoch - snapshot_epoch) / 86400 ))
}

council_benchmark_freshness_weight() {
    local age_days="${1:-999}"

    awk -v age="$age_days" 'BEGIN {
        if (age <= 30) {
            printf "%.4f", 1.0
        } else if (age <= 90) {
            printf "%.4f", (90 - age) / 60.0
        } else {
            printf "%.4f", 0.0
        }
    }'
}

council_load_benchmark_metadata() {
    COUNCIL_BENCHMARK_USED="false"
    COUNCIL_BENCHMARK_SNAPSHOT=""
    COUNCIL_BENCHMARK_FRESHNESS=""
    COUNCIL_BENCHMARK_FRESHNESS_WEIGHT="0"

    if [[ "$COUNCIL_BENCHMARK" == "off" ]]; then
        return 0
    fi

    local root manifest csv snapshot freshness
    root="$(council_plugin_root)"
    manifest="$root/data/benchmarks/bullshitbench-v2-manifest.json"

    if [[ ! -f "$manifest" ]]; then
        if [[ "$COUNCIL_BENCHMARK" == "on" ]]; then
            council_error_usage "benchmark metadata missing: $manifest"
            return 2
        fi
        return 0
    fi

    snapshot="$(jq -r '.snapshot_generated_at // empty' "$manifest" 2>/dev/null || true)"
    csv="$(jq -r '.csv // empty' "$manifest" 2>/dev/null || true)"
    if [[ -z "$snapshot" || -z "$csv" || ! -f "$root/data/benchmarks/$csv" ]]; then
        if [[ "$COUNCIL_BENCHMARK" == "on" ]]; then
            council_error_usage "benchmark metadata invalid"
            return 2
        fi
        return 0
    fi

    freshness="$(council_snapshot_age_days "$snapshot")"
    if (( freshness > 90 )); then
        if [[ "$COUNCIL_BENCHMARK" == "on" ]]; then
            council_error_usage "benchmark metadata is older than 90 days"
            return 2
        fi
        COUNCIL_BENCHMARK_SNAPSHOT="$snapshot"
        COUNCIL_BENCHMARK_FRESHNESS="$freshness"
        return 0
    fi

    COUNCIL_BENCHMARK_USED="true"
    COUNCIL_BENCHMARK_SNAPSHOT="$snapshot"
    COUNCIL_BENCHMARK_FRESHNESS="$freshness"
    COUNCIL_BENCHMARK_FRESHNESS_WEIGHT="$(council_benchmark_freshness_weight "$freshness")"
}

council_benchmark_signal() {
    local provider_org="$1"
    local model="$2"

    if [[ "$COUNCIL_BENCHMARK_USED" != "true" ]]; then
        printf '0.0000'
        return 0
    fi

    local root manifest csv model_name
    root="$(council_plugin_root)"
    manifest="$root/data/benchmarks/bullshitbench-v2-manifest.json"
    csv="$(jq -r '.csv // empty' "$manifest" 2>/dev/null || true)"
    [[ -n "$csv" && -f "$root/data/benchmarks/$csv" ]] || { printf '0.0000'; return 0; }

    model_name="${model##*/}"
    awk -F, \
        -v provider="$provider_org" \
        -v model="$model_name" \
        -v weight="${COUNCIL_BENCHMARK_FRESHNESS_WEIGHT:-0}" \
        'NR > 1 && $1 == provider && $2 == model {
            signal = ($4 + 0) * (1.0 - ($5 + 0)) * (weight + 0)
            if (signal < 0) signal = 0
            if (signal > 1) signal = 1
            printf "%.4f", signal
            found = 1
            exit
        }
        END {
            if (!found) {
                printf "0.0000"
            }
        }' "$root/data/benchmarks/$csv"
}
