#!/usr/bin/env bash
# Claude Octopus Council command helpers.
# Source-safe: defines functions only.

COUNCIL_GOAL=""
COUNCIL_DOMAIN=""
COUNCIL_STYLE=""
COUNCIL_DEPTH=""
COUNCIL_MEMBERS=""
COUNCIL_RESOLVED_MEMBERS=""
COUNCIL_PERSONAS=""
COUNCIL_IMPLEMENT=""
COUNCIL_WORKTREE=""
COUNCIL_BENCHMARK=""
COUNCIL_PROVIDERS=""
COUNCIL_MAX_COST=""
COUNCIL_DRY_RUN=""
COUNCIL_JSON=""
COUNCIL_OUTPUT_DIR=""
COUNCIL_TASK=""
COUNCIL_RUN_DIR=""
COUNCIL_RUN_ID=""
COUNCIL_FIXTURE=""
COUNCIL_MEMBER_OVERRIDE_WARNING=""
COUNCIL_ESTIMATED_COST=""
COUNCIL_BENCHMARK_USED=""
COUNCIL_BENCHMARK_SNAPSHOT=""
COUNCIL_BENCHMARK_FRESHNESS=""
COUNCIL_PROVIDER_STATUS_JSON=""
COUNCIL_ROSTER_JSON=""

council_usage() {
    cat << EOF
Usage: $(basename "${0:-orchestrate.sh}") council [OPTIONS] <task>

Options:
  --goal advice|decision|plan|implement|review
  --domain auto|architecture|product|security|business|research|docs
  --style balanced|adversarial|implementation|executive|red-team
  --depth quick|standard|deep
  --members auto|3|5|7
  --persona <name>[,<name>]
  --implement never|after-approval|plan-only
  --worktree auto|on|off
  --benchmark auto|on|off
  --providers auto|claude,codex,gemini,opencode,openrouter
  --max-cost <usd>
  --dry-run
  --json
  --output-dir <path>

Budget values are USD decimal numbers only, for example: 2, 2.00, 0.50.
EOF
}

council_reset_defaults() {
    COUNCIL_GOAL="advice"
    COUNCIL_DOMAIN="auto"
    COUNCIL_STYLE="balanced"
    COUNCIL_DEPTH="standard"
    COUNCIL_MEMBERS="auto"
    COUNCIL_RESOLVED_MEMBERS=""
    COUNCIL_PERSONAS=""
    COUNCIL_IMPLEMENT="never"
    COUNCIL_WORKTREE="auto"
    COUNCIL_BENCHMARK="auto"
    COUNCIL_PROVIDERS="auto"
    COUNCIL_MAX_COST=""
    COUNCIL_DRY_RUN="false"
    COUNCIL_JSON="false"
    COUNCIL_OUTPUT_DIR=""
    COUNCIL_TASK=""
    COUNCIL_RUN_DIR=""
    COUNCIL_RUN_ID=""
    COUNCIL_FIXTURE="${OCTOPUS_COUNCIL_FIXTURE:-}"
    COUNCIL_MEMBER_OVERRIDE_WARNING="false"
    COUNCIL_ESTIMATED_COST="0.00"
    COUNCIL_BENCHMARK_USED="false"
    COUNCIL_BENCHMARK_SNAPSHOT=""
    COUNCIL_BENCHMARK_FRESHNESS=""
    COUNCIL_PROVIDER_STATUS_JSON='{}'
    COUNCIL_ROSTER_JSON='[]'
}

council_plugin_root() {
    if [[ -n "${PLUGIN_DIR:-}" ]]; then
        printf '%s\n' "$PLUGIN_DIR"
        return 0
    fi

    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    cd "$lib_dir/../.." && pwd -P
}

council_error_usage() {
    local message="$1"
    echo "council: $message" >&2
    echo "Run with --help for usage." >&2
}

council_validate_choice() {
    local flag="$1"
    local value="$2"
    local allowed="$3"

    case ",$allowed," in
        *,"$value",*) return 0 ;;
    esac

    council_error_usage "$flag must be one of: ${allowed//,/|}"
    return 2
}

council_validate_provider_list() {
    local providers="$1"
    local allowed="claude,codex,gemini,opencode,openrouter"

    if [[ "$providers" == "auto" ]]; then
        return 0
    fi

    if [[ "$providers" == *auto* ]]; then
        council_error_usage "--providers auto cannot be combined with an explicit provider list"
        return 2
    fi

    local provider
    IFS=',' read -r -a provider_list <<< "$providers"
    for provider in "${provider_list[@]}"; do
        provider="${provider// /}"
        if [[ -z "$provider" ]]; then
            council_error_usage "--providers contains an empty provider"
            return 2
        fi
        case ",$allowed," in
            *,"$provider",*) ;;
            *)
                council_error_usage "unknown provider '$provider'. Allowed providers: ${allowed//,/|}"
                return 2
                ;;
        esac
    done
}

council_validate_budget() {
    local value="$1"

    if [[ ! "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        echo "council: --max-cost must be a USD decimal value such as 2, 2.00, or 0.50." >&2
        return 2
    fi

    awk -v value="$value" 'BEGIN { printf "%.2f", value + 0 }'
}

council_resolve_defaults() {
    local depth_default_members=""
    local depth_default_cost=""
    case "$COUNCIL_DEPTH" in
        quick)
            depth_default_members="3"
            depth_default_cost="0.50"
            ;;
        standard)
            depth_default_members="5"
            depth_default_cost="2.00"
            ;;
        deep)
            depth_default_members="7"
            depth_default_cost="5.00"
            ;;
    esac

    if [[ "$COUNCIL_MEMBERS" == "auto" ]]; then
        COUNCIL_RESOLVED_MEMBERS="$depth_default_members"
    else
        COUNCIL_RESOLVED_MEMBERS="$COUNCIL_MEMBERS"
        if [[ "$COUNCIL_MEMBERS" != "$depth_default_members" ]]; then
            COUNCIL_MEMBER_OVERRIDE_WARNING="true"
        fi
    fi

    if [[ -z "$COUNCIL_MAX_COST" ]]; then
        COUNCIL_MAX_COST="$depth_default_cost"
    fi
}

council_estimate_cost() {
    local prompt_chars=${#COUNCIL_TASK}
    local input_tokens=$(( (prompt_chars + 3) / 4 ))
    input_tokens=$(( (input_tokens * 125 + 99) / 100 ))

    local multiplier="1.0"
    case "$COUNCIL_DEPTH" in
        quick) multiplier="0.75" ;;
        standard) multiplier="1.0" ;;
        deep) multiplier="1.5" ;;
    esac

    # Conservative mixed-provider default: $3/MTok input, $15/MTok output.
    local estimate
    estimate=$(awk \
        -v input="$input_tokens" \
        -v multiplier="$multiplier" \
        -v members="$COUNCIL_RESOLVED_MEMBERS" \
        'BEGIN {
            output = input * multiplier
            cost = members * (((input / 1000000.0) * 3.0) + ((output / 1000000.0) * 15.0))
            if (cost > 0 && cost < 0.01) {
                cost = 0.01
            }
            printf "%.4f", cost
        }')
    COUNCIL_ESTIMATED_COST="$estimate"
}

council_snapshot_age_days() {
    local snapshot="$1"
    local now_epoch snapshot_epoch

    now_epoch="$(date -u +%s)"
    snapshot_epoch="$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$snapshot" +%s 2>/dev/null || date -u -d "$snapshot" +%s 2>/dev/null || echo "$now_epoch")"

    echo $(( (now_epoch - snapshot_epoch) / 86400 ))
}

council_load_benchmark_metadata() {
    COUNCIL_BENCHMARK_USED="false"
    COUNCIL_BENCHMARK_SNAPSHOT=""
    COUNCIL_BENCHMARK_FRESHNESS=""

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
}

council_provider_command() {
    case "$1" in
        claude) echo "claude" ;;
        codex) echo "codex" ;;
        gemini) echo "gemini" ;;
        opencode) echo "opencode" ;;
        openrouter) echo "openrouter" ;;
        *) echo "$1" ;;
    esac
}

council_provider_org() {
    case "$1" in
        claude) echo "anthropic" ;;
        codex) echo "openai" ;;
        gemini) echo "google" ;;
        opencode) echo "opencode" ;;
        openrouter) echo "openrouter" ;;
        *) echo "$1" ;;
    esac
}

council_persona_default_provider() {
    case "$1" in
        strategy-analyst|exec-communicator) echo "claude" ;;
        research-synthesizer|business-analyst|finance-analyst|academic-writer|ux-researcher) echo "gemini" ;;
        *) echo "codex" ;;
    esac
}

council_persona_model() {
    case "$1" in
        strategy-analyst|exec-communicator) echo "anthropic/claude-sonnet-4.6" ;;
        research-synthesizer|business-analyst|finance-analyst|academic-writer|ux-researcher) echo "gemini-3-pro-preview" ;;
        code-reviewer) echo "gpt-5.3-codex-spark" ;;
        *) echo "gpt-5.3-codex" ;;
    esac
}

council_persona_seat() {
    case "$1" in
        strategy-analyst|research-synthesizer|exec-communicator|business-analyst) echo "chair" ;;
        security-auditor) echo "skeptic" ;;
        code-reviewer|test-automator) echo "verifier" ;;
        typescript-pro|python-pro|tdd-orchestrator) echo "implementer" ;;
        *) echo "advisor" ;;
    esac
}

council_provider_is_available() {
    local provider="$1"
    local status
    status="$(jq -r --arg provider "$provider" '.[$provider] // "missing"' <<< "$COUNCIL_PROVIDER_STATUS_JSON")"
    [[ "$status" == "available" ]]
}

council_pick_provider() {
    local preferred="$1"
    if council_provider_is_available "$preferred"; then
        echo "$preferred"
        return 0
    fi

    local provider providers="$COUNCIL_PROVIDERS"
    [[ "$providers" == "auto" ]] && providers="claude,codex,gemini,opencode,openrouter"
    IFS=',' read -r -a provider_list <<< "$providers"
    for provider in "${provider_list[@]}"; do
        provider="${provider// /}"
        if council_provider_is_available "$provider"; then
            echo "$provider"
            return 0
        fi
    done

    echo "$preferred"
}

council_roster_contains() {
    local persona="$1"
    jq -e --arg persona "$persona" 'any(.[]; .persona == $persona)' <<< "$COUNCIL_ROSTER_JSON" >/dev/null
}

council_add_roster_persona() {
    local persona="$1"
    local max="${COUNCIL_RESOLVED_MEMBERS:-3}"

    [[ -n "$persona" ]] || return 0
    if council_roster_contains "$persona"; then
        return 0
    fi

    local current_len
    current_len="$(jq 'length' <<< "$COUNCIL_ROSTER_JSON")"
    if (( current_len >= max )); then
        return 0
    fi

    local preferred_provider provider provider_org model seat benchmark_signal
    preferred_provider="$(council_persona_default_provider "$persona")"
    provider="$(council_pick_provider "$preferred_provider")"
    provider_org="$(council_provider_org "$provider")"
    model="$(council_persona_model "$persona")"
    seat="$(council_persona_seat "$persona")"
    benchmark_signal="null"

    if [[ "$COUNCIL_BENCHMARK_USED" == "true" ]]; then
        benchmark_signal="0.75"
    fi

    COUNCIL_ROSTER_JSON="$(jq -c \
        --arg seat "$seat" \
        --arg persona "$persona" \
        --arg provider "$provider" \
        --arg model "$model" \
        --arg provider_org "$provider_org" \
        --argjson benchmark_signal "$benchmark_signal" \
        '. + [{
            seat: $seat,
            persona: $persona,
            provider: $provider,
            model: $model,
            provider_org: $provider_org,
            score: null,
            benchmark_signal: $benchmark_signal
        }]' <<< "$COUNCIL_ROSTER_JSON")"
}

council_build_roster() {
    COUNCIL_ROSTER_JSON='[]'

    council_add_roster_persona "strategy-analyst"

    local persona
    if [[ -n "$COUNCIL_PERSONAS" ]]; then
        IFS=',' read -r -a pinned_personas <<< "$COUNCIL_PERSONAS"
        for persona in "${pinned_personas[@]}"; do
            persona="${persona// /}"
            council_add_roster_persona "$persona"
        done
    fi

    case "$COUNCIL_DOMAIN" in
        architecture) set -- backend-architect database-architect cloud-architect code-reviewer ;;
        product) set -- product-writer ux-researcher business-analyst code-reviewer ;;
        security) set -- security-auditor code-reviewer backend-architect test-automator ;;
        business) set -- business-analyst finance-analyst exec-communicator research-synthesizer ;;
        research) set -- research-synthesizer academic-writer business-analyst exec-communicator ;;
        docs) set -- exec-communicator docs-architect product-writer code-reviewer ;;
        *) set -- backend-architect security-auditor research-synthesizer code-reviewer exec-communicator business-analyst ;;
    esac

    for persona in "$@"; do
        council_add_roster_persona "$persona"
    done

    if [[ "$COUNCIL_STYLE" == "red-team" || "$COUNCIL_STYLE" == "adversarial" ]]; then
        council_add_roster_persona "security-auditor"
        council_add_roster_persona "code-reviewer"
    fi

    if [[ "$COUNCIL_GOAL" == "implement" || "$COUNCIL_STYLE" == "implementation" ]]; then
        council_add_roster_persona "typescript-pro"
        council_add_roster_persona "test-automator"
        council_add_roster_persona "code-reviewer"
    fi

    local filler=(backend-architect security-auditor research-synthesizer code-reviewer exec-communicator business-analyst test-automator typescript-pro docs-architect)
    for persona in "${filler[@]}"; do
        council_add_roster_persona "$persona"
    done
}

council_detect_providers() {
    local providers="$COUNCIL_PROVIDERS"
    if [[ "$providers" == "auto" ]]; then
        providers="claude,codex,gemini,opencode,openrouter"
    fi

    local json='{}'

    if [[ -n "${OCTOPUS_COUNCIL_PROVIDER_FIXTURE:-}" ]]; then
        local entry name status
        IFS=',' read -r -a fixture_entries <<< "$OCTOPUS_COUNCIL_PROVIDER_FIXTURE"
        for entry in "${fixture_entries[@]}"; do
            name="${entry%%:*}"
            status="${entry#*:}"
            [[ -n "$name" && -n "$status" && "$name" != "$status" ]] || continue
            json="$(jq -c --arg name "$name" --arg status "$status" '. + {($name): $status}' <<< "$json")"
        done
        COUNCIL_PROVIDER_STATUS_JSON="$json"
        return 0
    fi

    local provider cmd status
    IFS=',' read -r -a provider_list <<< "$providers"
    for provider in "${provider_list[@]}"; do
        cmd="$(council_provider_command "$provider")"
        if command -v "$cmd" >/dev/null 2>&1; then
            status="available"
        else
            status="missing"
        fi
        json="$(jq -c --arg name "$provider" --arg status "$status" '. + {($name): $status}' <<< "$json")"
    done

    COUNCIL_PROVIDER_STATUS_JSON="$json"
}

council_parse_args() {
    council_reset_defaults

    local positional=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                council_usage
                return 0
                ;;
            --goal)
                [[ $# -ge 2 ]] || { council_error_usage "--goal requires a value"; return 2; }
                COUNCIL_GOAL="$2"
                council_validate_choice "--goal" "$COUNCIL_GOAL" "advice,decision,plan,implement,review" || return 2
                shift 2
                ;;
            --domain)
                [[ $# -ge 2 ]] || { council_error_usage "--domain requires a value"; return 2; }
                COUNCIL_DOMAIN="$2"
                council_validate_choice "--domain" "$COUNCIL_DOMAIN" "auto,architecture,product,security,business,research,docs" || return 2
                shift 2
                ;;
            --style)
                [[ $# -ge 2 ]] || { council_error_usage "--style requires a value"; return 2; }
                COUNCIL_STYLE="$2"
                council_validate_choice "--style" "$COUNCIL_STYLE" "balanced,adversarial,implementation,executive,red-team" || return 2
                shift 2
                ;;
            --depth)
                [[ $# -ge 2 ]] || { council_error_usage "--depth requires a value"; return 2; }
                COUNCIL_DEPTH="$2"
                council_validate_choice "--depth" "$COUNCIL_DEPTH" "quick,standard,deep" || return 2
                shift 2
                ;;
            --members)
                [[ $# -ge 2 ]] || { council_error_usage "--members requires a value"; return 2; }
                COUNCIL_MEMBERS="$2"
                council_validate_choice "--members" "$COUNCIL_MEMBERS" "auto,3,5,7" || return 2
                shift 2
                ;;
            --persona)
                [[ $# -ge 2 ]] || { council_error_usage "--persona requires a value"; return 2; }
                COUNCIL_PERSONAS="$2"
                shift 2
                ;;
            --implement)
                [[ $# -ge 2 ]] || { council_error_usage "--implement requires a value"; return 2; }
                COUNCIL_IMPLEMENT="$2"
                council_validate_choice "--implement" "$COUNCIL_IMPLEMENT" "never,after-approval,plan-only" || return 2
                shift 2
                ;;
            --worktree)
                [[ $# -ge 2 ]] || { council_error_usage "--worktree requires a value"; return 2; }
                COUNCIL_WORKTREE="$2"
                council_validate_choice "--worktree" "$COUNCIL_WORKTREE" "auto,on,off" || return 2
                shift 2
                ;;
            --benchmark)
                [[ $# -ge 2 ]] || { council_error_usage "--benchmark requires a value"; return 2; }
                COUNCIL_BENCHMARK="$2"
                council_validate_choice "--benchmark" "$COUNCIL_BENCHMARK" "auto,on,off" || return 2
                shift 2
                ;;
            --providers)
                [[ $# -ge 2 ]] || { council_error_usage "--providers requires a value"; return 2; }
                COUNCIL_PROVIDERS="${2// /}"
                shift 2
                ;;
            --max-cost)
                [[ $# -ge 2 ]] || { council_error_usage "--max-cost requires a value"; return 2; }
                COUNCIL_MAX_COST="$(council_validate_budget "$2")" || return 2
                shift 2
                ;;
            --dry-run)
                COUNCIL_DRY_RUN="true"
                shift
                ;;
            --json)
                COUNCIL_JSON="true"
                shift
                ;;
            --output-dir)
                [[ $# -ge 2 ]] || { council_error_usage "--output-dir requires a value"; return 2; }
                COUNCIL_OUTPUT_DIR="$2"
                shift 2
                ;;
            --*)
                council_error_usage "unknown option: $1"
                return 2
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    COUNCIL_TASK="${positional[*]}"
    council_validate_provider_list "$COUNCIL_PROVIDERS" || return 2
    council_resolve_defaults
    council_load_benchmark_metadata || return $?
    council_detect_providers || return $?
}

council_create_run_dir() {
    local parent="$COUNCIL_OUTPUT_DIR"
    if [[ -z "$parent" ]]; then
        parent="${WORKSPACE_DIR:-${HOME}/.claude-octopus}/councils"
    fi

    mkdir -p "$parent" || return 1

    local timestamp
    timestamp="$(date -u +%Y%m%d-%H%M%S)"
    local suffix
    suffix="$(printf '%06x' "$$")"
    COUNCIL_RUN_ID="${timestamp}-${suffix}"
    COUNCIL_RUN_DIR="${parent}/${COUNCIL_RUN_ID}"

    local attempts=0
    while [[ -e "$COUNCIL_RUN_DIR" ]]; do
        attempts=$((attempts + 1))
        COUNCIL_RUN_ID="${timestamp}-${suffix}-${attempts}"
        COUNCIL_RUN_DIR="${parent}/${COUNCIL_RUN_ID}"
    done

    mkdir -p "$COUNCIL_RUN_DIR/responses" "$COUNCIL_RUN_DIR/critiques" || return 1
}

council_write_summary_json() {
    local status="$1"
    local summary_path="${COUNCIL_RUN_DIR}/summary.json"

    council_estimate_cost
    council_build_roster

    jq -n \
        --arg run_id "$COUNCIL_RUN_ID" \
        --arg status "$status" \
        --arg goal "$COUNCIL_GOAL" \
        --arg domain "$COUNCIL_DOMAIN" \
        --arg style "$COUNCIL_STYLE" \
        --arg depth "$COUNCIL_DEPTH" \
        --arg members "$COUNCIL_RESOLVED_MEMBERS" \
        --arg benchmark "$COUNCIL_BENCHMARK" \
        --arg benchmark_used "$COUNCIL_BENCHMARK_USED" \
        --arg benchmark_snapshot "$COUNCIL_BENCHMARK_SNAPSHOT" \
        --arg benchmark_freshness "$COUNCIL_BENCHMARK_FRESHNESS" \
        --arg max_cost "$COUNCIL_MAX_COST" \
        --arg estimated_cost "$COUNCIL_ESTIMATED_COST" \
        --arg providers "$COUNCIL_PROVIDERS" \
        --argjson provider_status "$COUNCIL_PROVIDER_STATUS_JSON" \
        --arg implement "$COUNCIL_IMPLEMENT" \
        --arg worktree "$COUNCIL_WORKTREE" \
        --arg fixture "$COUNCIL_FIXTURE" \
        --arg member_override_warning "$COUNCIL_MEMBER_OVERRIDE_WARNING" \
        --arg task "$COUNCIL_TASK" \
        --arg personas_requested "$COUNCIL_PERSONAS" \
        --argjson council_roster "$COUNCIL_ROSTER_JSON" \
        '{
          run_id: $run_id,
          command: "council",
          status: $status,
          task: $task,
          goal: $goal,
          domain: $domain,
          style: $style,
          depth: $depth,
          members: ($members | tonumber),
          personas_requested: $personas_requested,
          benchmark: {
            mode: $benchmark,
            snapshot_generated_at: (if $benchmark_snapshot == "" then null else $benchmark_snapshot end),
            freshness_days: (if $benchmark_freshness == "" then null else ($benchmark_freshness | tonumber) end),
            used: ($benchmark_used == "true")
          },
          budget: {
            max_cost_usd: ($max_cost | tonumber),
            estimated_cost_usd: ($estimated_cost | tonumber),
            aborted_for_cost: false
          },
          quorum: {
            required_non_chair: (if $depth == "quick" then 1 else 2 end),
            received_non_chair: 0,
            met: false
          },
          providers: $providers,
          provider_status: $provider_status,
          warnings: {
            member_override: ($member_override_warning == "true")
          },
          council: $council_roster,
          veto: {
            triggered: ($fixture == "critical-veto"),
            severity: (if $fixture == "critical-veto" then "critical" else null end),
            confidence: (if $fixture == "critical-veto" then 1.0 else null end),
            reason: (if $fixture == "critical-veto" then "fixture: implementation plan lacks tests for a high-risk change" else null end),
            overridden: false
          },
          artifacts: {
            synthesis: "synthesis.md",
            responses_dir: "responses",
            critiques_dir: "critiques"
          },
          implementation: {
            permission: $implement,
            worktree: $worktree,
            gate_a_approved: false,
            gate_b_approved: false,
            handoff: null
          },
          fixture: (if $fixture == "" then null else $fixture end)
        }' > "$summary_path"
}

council_run() {
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        council_usage
        return 0
    fi

    council_parse_args "$@" || return $?

    if [[ -z "$COUNCIL_TASK" ]]; then
        council_error_usage "missing task"
        return 2
    fi

    council_create_run_dir || return 1

    if [[ "$COUNCIL_DRY_RUN" == "true" ]]; then
        council_write_summary_json "dry-run" || return 1
        if [[ "$COUNCIL_JSON" == "true" ]]; then
            cat "${COUNCIL_RUN_DIR}/summary.json"
        else
            echo "Council dry run complete: ${COUNCIL_RUN_DIR}/summary.json"
        fi
        return 0
    fi

    council_write_summary_json "partial" || return 1
    echo "Council first slice is installed. Use --dry-run for deterministic preflight until provider fanout ships."
}
