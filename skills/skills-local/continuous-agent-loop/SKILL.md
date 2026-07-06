---
name: continuous-agent-loop
description: Use this ECC-derived skill in Codex to design bounded autonomous agent loops with quality gates, evals, recovery controls, stop conditions, and evidence reporting.
metadata:
  origin: ECC
---

# Continuous Agent Loop

This is the v1.8+ canonical ECC loop skill name. In Codex, prefer bounded loops with explicit verification, budget, and stop rules.

## Loop Selection Flow

```text
Start
  |
  +-- Need strict CI/PR control? -- yes --> continuous-pr
  |
  +-- Need RFC decomposition? -- yes --> rfc-dag
  |
  +-- Need exploratory parallel generation? -- yes --> infinite
  |
  +-- default --> sequential
```

## Combined Pattern

Recommended production stack:
1. RFC decomposition (`ralphinho-rfc-pipeline`)
2. quality gates (`plankton-code-quality` + `/quality-gate`)
3. eval loop (`eval-harness`)
4. session persistence (`nanoclaw-repl`)

## Failure Modes

- loop churn without measurable progress
- repeated retries with same root cause
- merge queue stalls
- cost drift from unbounded escalation

## Recovery

- freeze loop
- run `/harness-audit`
- reduce scope to failing unit
- replay with explicit acceptance criteria
