# gsd-multi-model

## What This Is

A multi-model development framework that combines Claude Code and Codex CLI into a unified, spec-driven workflow. Skills, task-splitting heuristics, worktree automation, Codex execution wrapper, orchestration logic, and upstream sync tooling — installed via `npx gsd-multi-model` (or locally via `./bin/cli.sh`) and bootstrapped per-project with `/init-gsd`.

## Core Value

Structured dual-tool workflow that eliminates per-session re-explanation, splits work by tool strengths automatically, and drives itself through the full planning-to-verification loop without manual step-by-step invocation.

## Current State

**Shipped:** v1.2 Upstream Sync (2026-03-06)
**Total:** 8 phases, 16 plans across 3 milestones
**Production code:** ~5,000 LOC across bin/, skills/, global/, rules/, install scripts

The full dual-tool loop is proven end-to-end: bootstrap → plan → split → parallel Codex execution in worktree → merge → cross-review. All scripts have integration test suites. Addon stays in sync with base GSD via version pinning and single-command update wrapper.

**v1.3 (superseded):** Local-first install goals were replaced by the npx-based `bin/cli.sh` approach, which achieves zero-risk install without modifying global GSD setup. Rolled into v2.0.

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
- ✓ Version pinning with `gsd-compat.json` tested range manifest — v1.2
- ✓ Install-time compatibility check with warn-only behavior — v1.2
- ✓ Update wrapper with three-stage pipeline and structured exit codes — v1.2

### Active

## Current Milestone: v2.0 Harness Engineering

**Goal:** Close the gaps between gsd-multi-model and the harness engineering discipline — transform from a manual-step framework into an autonomous, self-driving system with deterministic quality gates and entropy management.

**Gap analysis source:** OpenAI "Harness Engineering" (2026), Martin Fowler analysis, InfoQ coverage.

**Target features:**
- Autonomous orchestrator that chains discuss → plan → execute → verify → advance
- Deterministic lint/test gates that block bad code before commit
- Architectural constraint enforcement via machine-readable rules
- Scheduled entropy management (doc consistency, constraint scanning)
- Observability integration for executor agents
- NPM-publishable package for `npx gsd-multi-model` distribution

### Out of Scope

- Gemini, OpenCode, or other AI tool integration — Claude + Codex only
- Mobile/web UI — CLI-first approach
- Cloud hosting — local development tool
- Harness A/B testing framework — matters at team scale, not solo
- Real-time streaming from Codex — Codex CLI handles its own output
- Custom model routing beyond profiles — fixed quality/balanced/budget tiers sufficient

## Context

Three milestones shipped in 5 days. v1.0 delivered planning-side integration (3 skills + task routing). v1.1 delivered execution-side integration (installer hardening, worktree lifecycle, Codex runner, end-to-end demo). v1.2 delivered upstream sync tooling (version pinning, compat check, update wrapper). v1.3 was superseded by v2.0 — its local-first install goals were solved by the npx CLI approach.

Gap analysis against OpenAI's harness engineering framework identified 7 gaps: orchestration (major), deterministic gates (major), entropy management (moderate), observability (moderate), progressive context disclosure (minor), harness versioning (minor), and NPM distribution (minor).

Tech stack: Claude Code skills (markdown), GSD agents (prompt engineering), Bash (bin/ scripts, install, tests), Node.js (npx CLI entry point).

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
| Addon overlay pattern (not fork) | ✓ Good — GSD updates don't destroy customizations |
| Version range pinning (not exact version) | ✓ Good — flexibility without breaking |
| Install-time checks only (not runtime) | ✓ Good — lean, no overhead during normal use |
| npx CLI replaces monolithic install.sh | ✓ Good — skills-only default, opt-in layers |
| v1.3 superseded by v2.0 | ✓ Good — npx approach solves local-first better |

## Constraints

- Skills must work across Claude Code sessions without re-explaining
- All instruction files must stay under 200 lines for >92% rule adherence
- No external dependencies beyond Claude Code and Codex CLI
- Orchestrator must work within Claude Code's context/session model (no external daemon required)

## Target Users

Developers who use both Claude Code and Codex CLI and want a repeatable harness to combine them.

## Success Criteria

✓ Achieved: End-to-end demo runs full loop without manual intervention — `/init-gsd` → plan → auto-split → Codex builds in worktree → cross-review.

✓ Achieved: Upstream sync with single-command update.

Pending: Autonomous orchestrator drives full phase lifecycle without manual `/clear` + next-command sequences.

Pending: Deterministic gates block bad code before commit (not just advisory verification).

---
*Last updated: 2026-03-11 after v2.0 milestone started*
