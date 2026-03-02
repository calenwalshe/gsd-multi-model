# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — Dual-Tool Framework MVP

**Shipped:** 2026-03-02
**Phases:** 2 | **Plans:** 5 | **Sessions:** 2

### What Was Built
- 3 production-grade Claude Code skills (init-gsd, codex-review, gsd-codex-verify)
- 4-signal task routing heuristic embedded in gsd-planner agent
- PLAN.md XML schema extension with executor/confidence attributes
- Plan checker Dimension 9 for routing validation

### What Worked
- GSD subagent delegation kept orchestrator context lean (~10-15%)
- Plan → check → revise loop caught issues before execution
- Compound keyword patterns avoided false positive routing on single words
- Conservative routing default (ambiguous → Claude) prevented unsafe autonomous execution

### What Was Inefficient
- Phase 1 skills live outside git repo (~/.claude/) — commits tracked planning artifacts only, not the actual skill files
- Milestone scoped too ambitiously (5 phases) — shipped 2/5, deferred rest to v1.1
- UAT tests for prompt-engineering changes are inherently limited to grep checks on file content

### Patterns Established
- Embed heuristics directly in agent prompts rather than creating standalone modules
- Phase-gated validation (skip new checks for older phase plans)
- Severity tiering in checker: INFO (advisory), ISSUE (planner-fixable), ERROR (blocker)

### Key Lessons
1. Scope milestones to what's independently shippable — planning-side integration (phases 1-2) is useful without execution-side (phases 3-5)
2. Agent prompt files are the primary "code" in this project — treat edits with the same rigor as production code
3. Backward compatibility matters even in prompt engineering — old plans shouldn't break with new validation

### Cost Observations
- Model mix: ~40% opus (planning/orchestration), ~50% sonnet (research/execution/verification), ~10% haiku
- Sessions: 2 (one per phase)
- Notable: Entire milestone completed in a single day (~6 hours wall time)

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0 | 2 | 2 | Initial process — established GSD dual-tool workflow |

### Top Lessons (Verified Across Milestones)

1. Conservative defaults in routing heuristics prevent costly mistakes
2. Embedding logic in existing agent prompts beats creating new standalone components
