# gsd-multi-model

## What This Is

A multi-model development framework that combines Claude Code and Codex CLI into a unified, spec-driven workflow. Skills, task-splitting heuristics, and orchestration logic — installed via a single `/init-gsd` command.

## Core Value

Structured dual-tool workflow that eliminates per-session re-explanation and splits work by tool strengths automatically.

## Current Milestone: v1.1 Execution-Side Integration

**Goal:** Make the dual-tool workflow actually execute — worktree isolation, Codex runner, cross-review wiring, and a complete end-to-end demo.

**Target features:**
- Worktree automation for parallel Codex execution
- Codex execution wrapper (`bin/codex-task.sh`)
- End-to-end demo of full workflow loop
- Installer hardening with dependency checks
- Global config templates for Claude and Codex

## Requirements

### Validated

- ✓ `/init-gsd` bootstrap with idempotency, stack detection, full project scaffolding — v1.0
- ✓ `/codex-review` cross-model review with Codex invocation and severity reporting — v1.0
- ✓ `/gsd-codex-verify` dual verification gate with JSONL parsing and structured reports — v1.0
- ✓ Task-splitting heuristic with 4-signal analysis, type shortcuts, user overrides — v1.0

### Active

- [ ] Worktree automation for parallel Codex execution
- [ ] Codex execution wrapper (`bin/codex-task.sh`)
- [ ] End-to-end demo of full workflow loop
- [ ] Installer hardening with dependency checks
- [ ] Global config templates for Claude and Codex

### Out of Scope

- Gemini, OpenCode, or other AI tool integration — Claude + Codex only
- Mobile/web UI — CLI-first approach
- Cloud hosting — local development tool

## Context

Shipped v1.0 with planning-side integration complete: 3 production skills + task routing heuristic + plan checker validation. Execution-side (worktrees, Codex runner, cross-review wiring) deferred to v1.1.

Tech stack: Claude Code skills (markdown), GSD agents (prompt engineering), Bash (install/worktree scripts).
31 files, 7,173 lines added across 2 phases.

## Key Decisions

| Decision | Outcome |
|----------|---------|
| Compound keyword patterns for type shortcuts | ✓ Good — avoids false positives on single words |
| Conservative routing default (ambiguous → Claude) | ✓ Good — safer fallback |
| Embed heuristic in planner prompt, not standalone module | ✓ Good — zero new dependencies |
| Phase-gated validation (skip routing checks for Phase 1) | ✓ Good — backward compatible |
| Severity tiering in plan checker (INFO/ISSUE/ERROR) | ✓ Good — non-blocking advisories |

## Constraints

- Skills must work across Claude Code sessions without re-explaining
- All instruction files must stay under 200 lines for >92% rule adherence
- No external dependencies beyond Claude Code and Codex CLI

## Target Users

Developers who use both Claude Code and Codex CLI and want a repeatable harness to combine them.

## Success Criteria

End-to-end demo: `/init-gsd` → plan → auto-split → Codex builds in worktree → cross-review. Full loop without manual intervention beyond initial project decisions.

---
*Last updated: 2026-03-02 after v1.1 milestone start*
