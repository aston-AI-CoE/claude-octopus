#!/usr/bin/env bash
# Probe result helpers shared by workflow analysis and synthesis.

probe_result_output_chars() {
    local file="$1"
    [[ -f "$file" ]] || { echo 0; return 0; }

    awk '
        BEGIN { in_output = 0; chars = 0 }
        /^## Output[[:space:]]*$/ { in_output = 1; next }
        /^## Status:/ { in_output = 0; next }
        in_output {
            if ($0 ~ /^```[[:space:]]*$/) next
            if ($0 ~ /^[[:space:]]*$/) next
            chars += length($0)
        }
        END { print chars + 0 }
    ' "$file" 2>/dev/null || echo 0
}

probe_result_file_status() {
    local file="$1"
    [[ -f "$file" ]] || { echo "failed:missing-file"; return 0; }

    local output_chars
    output_chars="$(probe_result_output_chars "$file")"
    output_chars="${output_chars:-0}"
    [[ "$output_chars" =~ ^[0-9]+$ ]] || output_chars=0

    if grep -q "Status: SUCCESS" "$file" 2>/dev/null; then
        if [[ "$output_chars" -gt 0 ]]; then
            echo "success:"
        else
            echo "failed:empty-output"
        fi
    elif grep -q "Status: TIMEOUT" "$file" 2>/dev/null; then
        if [[ "$output_chars" -gt 0 ]]; then
            echo "timeout:partial-output"
        else
            echo "failed:timeout-empty"
        fi
    elif grep -q "Status: FAILED" "$file" 2>/dev/null; then
        if [[ "$output_chars" -gt 0 ]]; then
            echo "degraded:failed-with-output"
        else
            echo "failed:provider-failed"
        fi
    elif [[ "$output_chars" -gt 0 ]]; then
        echo "degraded:missing-status"
    else
        echo "failed:empty-output"
    fi
}

probe_result_file_is_usable() {
    local classification status
    classification="$(probe_result_file_status "$1")"
    status="${classification%%:*}"

    case "$status" in
        success|degraded|timeout) return 0 ;;
        *) return 1 ;;
    esac
}
