#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$PROJECT_ROOT/tests/helpers/test-framework.sh"
test_suite "Native First Routing"

SKILL_FILE="$PROJECT_ROOT/skills/skill-native-escalation-routing/SKILL.md"
PLUGIN_JSON="$PROJECT_ROOT/.claude-plugin/plugin.json"

test_case "native-first routing skill exists and is registered"
if assert_file_exists "$SKILL_FILE" "portable skill directory contains SKILL.md" && \
   assert_file_contains "$SKILL_FILE" '^name: skill-native-escalation-routing$' "skill has expected frontmatter name" && \
   assert_file_contains "$SKILL_FILE" 'Claude-native first' "skill documents Claude-native first policy" && \
   assert_file_contains "$SKILL_FILE" '/review' "skill documents /review routing" && \
   assert_file_contains "$SKILL_FILE" '/security-review' "skill documents /security-review routing" && \
   assert_file_contains "$SKILL_FILE" '/init' "skill documents /init routing" && \
   assert_file_contains "$SKILL_FILE" 'multiple model opinions' "skill documents Octopus escalation criteria" && \
   assert_file_contains "$PLUGIN_JSON" '\./skills/skill-native-escalation-routing' "plugin.json registers portable skill directory"; then
    test_pass
else
    if [[ $TESTS_FAILED -eq 0 ]]; then
        test_fail "native-first routing skill or plugin registration check failed"
    fi
fi

test_summary
