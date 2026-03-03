# gsd-multi-model

## What This Is

A multi-model development framework that combines Claude Code and Codex CLI into a unified, spec-driven workflow. Skills, task-splitting heuristics, worktree automation, Codex execution wrapper, and orchestration logic — installed via a single `bash install.sh` command and bootstrapped per-project with `/init-gsd`.

## Core Value

Structured dual-tool workflow that eliminates per-session re-explanation and splits work by tool strengths automatically.

## Current State

**Shipped:** v1.1 Execution-Side Integration (2026-03-03)
**Total:** 6 phases, 14 plans, 77 files, 14,484 lines across 2 milestones

The full dual-tool loop is proven end-to-end: bootstrap → plan → split → parallel Codex execution in worktree → merge → cross-review. All scripts have integration test suites.

## Requirements

### Validated

- ✓ `/init-gsd` bootstrap with idempotency, stack detection, full project scaffolding — v1.0
- ✓ `/codex-review` cross-model review with Codex invocation and severity reporting — v1.0
- ✓ `/gsd-codex-verify` dual verification gate with JSONL parsing and structured reports — v1.0
- ✓ Task-splitting heuristic with 4-signal analysis, type shortcuts, user overrides — v1.0
- ✓ Installer hardening with pre-flight checks, integrity validation, ANSI output — v1.1
- ✓ Global config templates for Claude and Codex (non-destructive install) — v1.1
- ✓ Worktree automation for parallel Codex execution — v1.1
- ✓ Codex execution wrapper with XML parsing, context injection, structured JSON output — v1.1
- ✓ End-to-end demo proving full workflow loop — v1.1

### Active

(None — planning next milestone)

### Out of Scope

- Gemini, OpenCode, or other AI tool integration — Claude + Codex only
- Mobile/web UI — CLI-first approach
- Cloud hosting — local development tool
- Real-time streaming from Codex — Codex CLI handles its own output
- Custom model routing — fixed Claude/Codex split is sufficient

## Context

Two milestones shipped in 2 days. v1.0 delivered planning-side integration (3 skills + task routing). v1.1 delivered execution-side integration (installer hardening, worktree lifecycle, Codex runner, end-to-end demo).

Tech stack: Claude Code skills (markdown), GSD agents (prompt engineering), Bash (bin/ scripts, install, tests).
Production code: 4,504 LOC across bin/, skills/, global/, rules/, install scripts.

## Key Decisions

| Decision | Outcome |
|----------|---------|
| Compound keyword patterns for type shortcuts | ✓ Good — avoids false positives on single words |
| Conservative routing default (ambiguous → Claude) | ✓ Good — safer fallback |
| Embed heuristic in planner prompt, not standalone module | ✓ Good — zero new dependencies |
| Phase-gated validation (skip routing checks for Phase 1) | ✓ Good — backward compatible |
| Human-readable to stderr, JSON to stdout | ✓ Good — clean piping for all bin/ scripts |
| Shell-only XML parsing with awk/grep/sed | ✓ Good — zero external dependencies |
| Confidence routing: high=full-auto, medium=default, low=skip | ✓ Good — safe Codex invocation |
| Temp file state sharing in demo (avoid subshell var loss) | ✓ Good — reliable inter-stage communication |
| Simulated init-gsd in demo (skill not standalone script) | ✓ Good — pragmatic workaround |

## Constraints

- Skills must work across Claude Code sessions without re-explaining
- All instruction files must stay under 200 lines for >92% rule adherence
- No external dependencies beyond Claude Code and Codex CLI

## Target Users

Developers who use both Claude Code and Codex CLI and want a repeatable harness to combine them.

## Success Criteria

✓ Achieved: End-to-end demo runs full loop without manual intervention — `/init-gsd` → plan → auto-split → Codex builds in worktree → cross-review. `bash bin/demo.sh` proves it in 7 stages.

---
*Last updated: 2026-03-03 after v1.1 milestone completion*
