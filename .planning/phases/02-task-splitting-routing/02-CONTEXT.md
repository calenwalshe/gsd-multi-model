# Phase 2: Task Splitting & Routing - Context

**Gathered:** 2026-03-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement heuristic-based task classification that auto-tags planned tasks as `executor="claude"` or `executor="codex"` during `/gsd:plan-phase`. Users can override any classification. This phase does NOT implement Codex execution (Phase 3) or cross-review wiring (Phase 4).

</domain>

<decisions>
## Implementation Decisions

### Classification signals
- Use 4-signal heuristic: scope (file count), spec clarity, isolation, error cost
- Conservative routing: default to Claude unless ALL signals indicate Codex is safe
- Add task-type shortcuts: tasks labeled "test", "script", "config", "docs" auto-route to Codex; "architecture", "refactor", "debug" auto-route to Claude
- Type shortcuts override signal analysis (fast path) — signal analysis is the fallback for unlabeled tasks

### Where the heuristic lives
- Embed classification rules directly in the gsd-planner agent's prompt/instructions
- Planner already creates tasks — it also tags them with `executor` attribute
- No standalone module needed at this stage
- PLAN.md XML schema extended: `<task executor="claude|codex" confidence="high|medium|low">`

### Override mechanism
- Interactive review step after plan generation: Claude presents task routing summary, asks "any overrides?"
- Users can also edit PLAN.md XML directly (change executor attribute) at any time
- Overrides persist — re-running planner preserves manually set executors

### Edge case / ambiguity handling
- Default to Claude when ambiguous (safer — Claude handles anything)
- Tag ambiguous tasks with `confidence="low"` so user can spot them in review
- Never block planning to ask about routing — decide and let user override

### Claude's Discretion
- Exact signal weights and thresholds
- How to extract signals from task descriptions (keyword matching, pattern analysis)
- PLAN.md XML formatting details
- How to present the routing summary during review

</decisions>

<specifics>
## Specific Ideas

- The routing summary should be a simple table: task name, executor, confidence, reason
- Keep the heuristic dead simple — this is v1, can be refined based on real usage in later phases
- Research already has a solid signal framework (Section 2 of task-splitting.md) — build on that, don't reinvent

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `.planning/research/task-splitting.md`: Comprehensive research with signal framework, algorithm pseudocode, and implementation recommendations
- `skills/gsd-codex-verify/SKILL.md`: Already has JSONL parsing patterns and Codex integration patterns to reference

### Established Patterns
- GSD planner agent (`gsd-planner` subagent type) creates PLAN.md files with XML task elements
- Skills use YAML frontmatter + markdown instruction body pattern
- All state persists in `.planning/` directory

### Integration Points
- `gsd-planner` agent: Where classification logic gets embedded
- PLAN.md XML schema: Where `executor` attribute gets added to `<task>` elements
- `/gsd:execute-phase` workflow: Downstream consumer — will read `executor` tags in Phase 3 to route tasks

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-task-splitting-routing*
*Context gathered: 2026-03-02*
