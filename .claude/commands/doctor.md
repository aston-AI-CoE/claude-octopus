---
command: doctor
description: "Run diagnostic checks on the Octopus plugin and environment"
aliases:
  - diagnostic
  - checkup
---

# Doctor - Plugin Diagnostics

**Your first output line MUST be:** `🐙 Octopus Doctor`

## Step 1: Initialize Diagnostics

```javascript
AskUserQuestion({
  questions: [
    {
      question: "Which diagnostics would you like to run?",
      header: "Diagnostic Scope",
      multiSelect: true,
      options: [
        {label: "Environment", description: "Check dependencies and shell environment"},
        {label: "Registry", description: "Verify tool registration and indexing"},
        {label: "Providers", description: "Check LLM CLI connectivity"},
        {label: "Storage", description: "Check results directory and permissions"}
      ]
    }
  ]
})
```

## Step 2: Execution

Run the diagnostic script:

```bash
bash "${HOME}/.claude-octopus/plugin/scripts/doctor.sh"
```

