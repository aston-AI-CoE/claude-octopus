#!/usr/bin/env bash
# provider-allowlist.sh - Shared OCTO_ALLOWED_PROVIDERS helpers.
#
# OCTO_ALLOWED_PROVIDERS is a space/comma separated list of provider names.
# When unset, every detected provider is allowed. When set, scripts should
# treat non-listed providers as unavailable even if their CLI/API key exists.

octo_normalize_provider_name() {
    printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr -d ','
}

octo_provider_allowed() {
    local provider
    provider="$(octo_normalize_provider_name "${1:-}")"
    [[ -n "$provider" ]] || return 1

    if [[ -z "${OCTO_ALLOWED_PROVIDERS:-}" ]]; then
        return 0
    fi

    local token normalized
    # shellcheck disable=SC2086 # Intentional word splitting: space separated allowlist.
    for token in ${OCTO_ALLOWED_PROVIDERS//,/ }; do
        normalized="$(octo_normalize_provider_name "$token")"
        [[ -n "$normalized" ]] || continue

        [[ "$provider" == "$normalized" ]] && return 0

        case "$normalized" in
            claude|anthropic|sonnet)
                case "$provider" in
                    claude|claude-sonnet|claude-opus|sonnet) return 0 ;;
                esac
                ;;
            codex|openai)
                case "$provider" in
                    codex|codex-*) return 0 ;;
                esac
                ;;
            gemini|google)
                case "$provider" in
                    gemini|gemini-*) return 0 ;;
                esac
                ;;
            cursor|cursor-agent|xai)
                [[ "$provider" == "cursor-agent" ]] && return 0
                ;;
            local)
                [[ "$provider" == "ollama" ]] && return 0
                ;;
        esac
    done

    return 1
}
