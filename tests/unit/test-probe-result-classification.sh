#!/usr/bin/env bash
# Regression checks for probe result classification.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Probe result classification"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/workflows.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/progressive.sh"

RESULT_DIR="$(mktemp -d)"
trap 'rm -rf "$RESULT_DIR"' EXIT

header_only="$RESULT_DIR/codex-probe-123-0.md"
cat > "$header_only" <<'EOF'
# Agent: codex
# Task ID: probe-123-0
# Role: researcher
# Phase: probe
# Prompt: Validate Writer claims.
# Started: Tue Jun  2 00:44:17 BST 2026

## Output
```
EOF

partial_body="$RESULT_DIR/gemini-probe-123-1.md"
cat > "$partial_body" <<'EOF'
# Agent: gemini
# Task ID: probe-123-1

## Output
```
Writer AI Studio appears to provide tool calling and deployment, but this answer was interrupted before a status marker was written.
EOF

success_body="$RESULT_DIR/claude-sonnet-probe-123-2.md"
cat > "$success_body" <<'EOF'
# Agent: claude-sonnet
# Task ID: probe-123-2

## Output
```
The hybrid threshold remains valid.
```

## Status: SUCCESS
EOF

test_case "header-only result is failed, not partial"
classification="$(probe_result_file_status "$header_only")"
if [[ "$classification" == "failed:empty-output" ]]; then
    test_pass
else
    test_fail "expected failed:empty-output for header-only file, got: ${classification:-<empty>}"
fi

test_case "body without status marker is degraded"
classification="$(probe_result_file_status "$partial_body")"
if [[ "$classification" == "degraded:missing-status" ]]; then
    test_pass
else
    test_fail "expected degraded:missing-status for answer body without marker, got: ${classification:-<empty>}"
fi

test_case "success marker remains success"
classification="$(probe_result_file_status "$success_body")"
if [[ "$classification" == "success:" ]]; then
    test_pass
else
    test_fail "expected success for status marker, got: ${classification:-<empty>}"
fi

test_case "partial synthesis skips header-only artifacts"
RESULTS_DIR="$RESULT_DIR/progressive"
mkdir -p "$RESULTS_DIR"
cp "$header_only" "$RESULTS_DIR/codex-probe-999-0.md"
cp "$success_body" "$RESULTS_DIR/gemini-probe-999-1.md"
partial="$(synthesize_probe_results_partial 999 "prompt" 1)"
if [[ "$partial" == *"Partial Synthesis (1/1 results)"* && \
      "$partial" == *"The hybrid threshold remains valid."* && \
      "$partial" != *"Validate Writer claims"* ]]; then
    test_pass
else
    test_fail "expected partial synthesis to include only usable output, got: ${partial:-<empty>}"
fi

test_summary
