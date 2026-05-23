---
description: "Multi-LLM council for advice, decision support, implementation plans, and gated implementation"
---

# Council

Use `/octo:council <task>` when the user wants a structured council of multiple LLM personas to advise, critique, synthesize, and optionally hand off an approved implementation plan.

Run through `skill-council`. Do not skip provider/cost preflight, quorum checks, or implementation gates.

## Examples

```text
/octo:council --depth quick --goal advice "Should we use Redis here?"
/octo:council --goal decision --domain architecture "Should this service stay monolithic?"
/octo:council --goal implement --implement plan-only "Refactor the auth flow"
/octo:council --dry-run --members 7 --persona finance-analyst "Review this pricing strategy"
```

## Flags

- `--goal advice|decision|plan|implement|review`
- `--domain auto|architecture|product|security|business|research|docs`
- `--style balanced|adversarial|implementation|executive|red-team`
- `--depth quick|standard|deep`
- `--members auto|3|5|7`
- `--persona <name>[,<name>]`
- `--implement never|after-approval|plan-only`
- `--worktree auto|on|off`
- `--benchmark auto|on|off`
- `--providers auto|claude,codex,gemini,opencode,openrouter`
- `--max-cost <usd>`
- `--dry-run`
- `--json`
- `--output-dir <path>`
