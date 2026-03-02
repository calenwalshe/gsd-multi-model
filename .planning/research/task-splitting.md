# AI Task Splitting & Multi-Model Orchestration Research

**Domain:** Task complexity classification, multi-model routing, parallel AI execution, cross-model verification
**Researched:** 2026-03-02
**Confidence:** MEDIUM-HIGH (Web search + official sources verify patterns; implementation details from emerging 2025-2026 ecosystem)

---

## Executive Summary

Building effective task-splitting heuristics for gsd-multi-model requires understanding five interconnected domains: (1) how to classify task complexity signals, (2) how multi-model systems route work in 2025-2026, (3) git worktree patterns for parallel AI execution, (4) cross-model verification strategies, and (5) how teams currently split AI tool responsibilities in practice.

**Key finding:** Task splitting should be **rule-based + heuristic** (fast, interpretable) with optional LLM-based classification fallback. 2026 industry standard is NOT "use the smartest model for everything" but rather "use the RIGHT model for each task type based on explicit signals."

**Critical insight:** Autonomous tools (Codex) excel at **well-defined, high-confidence tasks** (CRUD, tests, scripts, isolated refactoring). Complex tools (Claude Code) excel at **ambiguous, multi-file, architectural decisions, interactive debugging**. The split happens at **task boundary clarity**, not task size.

---

## 1. Task Complexity Classification Signals

### High-Level Decision Framework

Tasks split based on **CLARITY** and **ISOLATION** rather than just complexity:

| Signal | Autonomous-Friendly (Codex) | Complex-Friendly (Claude Code) |
|--------|---------------------------|-------------------------------|
| **Scope** | Single file, isolated CRUD | Multiple files, architectural impact |
| **Specification clarity** | Clear requirements, test cases provided | Ambiguous, requires design decisions |
| **Context boundary** | Self-contained, limited scope | Needs broader codebase understanding |
| **Error recovery** | Deterministic (tests verify), low stakes | High stakes, needs debugging skills |
| **Decision-making** | Follow rules/patterns | Trade-offs, design choices |

### Concrete Complexity Signals

**SIMPLE/AUTONOMOUS-FRIENDLY (Codex):**
- Single-file changes (function, method, variable)
- CRUD operations on known data structures
- Test writing (unit, integration tests)
- Script/CLI tool creation (self-contained logic)
- Documentation updates
- Structured refactoring (extract function, rename variables) within single file
- Configuration updates (JSON, YAML, ENV)
- Known bug fixes with clear reproduction cases
- Code formatting, linting fixes

**COMPLEX/CLAUDE-CODE-FRIENDLY:**
- Multi-file architectural changes
- Cross-service API design
- Error handling strategy redesigns
- Performance optimization requiring profiling
- Dependency upgrades with breaking changes
- Feature designs requiring state machine changes
- Debug sessions requiring interactive exploration
- Merge conflict resolution in complex codebases
- Refactoring decisions affecting public APIs ("floss refactoring")

### Research Support

**Multi-model routing in 2026:** Industry consensus from Google, Medium 2026 analysis, and academic literature supports **rule-based approaches** as the primary heuristic:
- Rule-based routing is "predictable, transparent, and fast to execute" — ideal for well-defined task categories
- LLM-based classification ("router LLM") used as **fallback** for edge cases, not primary method
- 2026 trend: "Winning teams use many models intelligently" by **pre-routing based on signals**, not post-selection

**Reference:** [Why 2026 Is the Year of Multi-Model Routing](https://medium.com/@MateCloud/why-2026-is-the-year-of-multi-model-routing-technical-challenges-and-system-design-2457dcdd2209) — Task routing before model selection eliminates wasted inference cycles.

---

## 2. Task Routing Heuristic Implementation

### Proposed Signal-Based Router

```
TASK CLASSIFICATION HEURISTIC:

1. SCOPE CHECK (read task description + affected files)
   - If "files_affected > 3 OR involves architecture": → COMPLEX
   - If "single file" OR "isolated CRUD": → SIMPLE

2. CLARITY CHECK (does requirement have ambiguity?)
   - If "requires design decision" OR "unclear test criteria": → COMPLEX
   - If "has test cases" OR "clear definition of done": → SIMPLE

3. ISOLATION CHECK (does change touch APIs, contracts, or global state?)
   - If "public API change" OR "affects other services": → COMPLEX
   - If "internal implementation only": → SIMPLE

4. ERROR COST CHECK (what happens if this fails?)
   - If "production impact" OR "blocks other work": → COMPLEX (needs interactive debugging)
   - If "low stakes" OR "caught by tests": → SIMPLE

DECISION:
- If SIMPLE in all checks → Route to CODEX
- If COMPLEX in any check → Route to CLAUDE CODE
- If ambiguous → Ask user OR fallback to CLAUDE CODE (safer)
```

### Why Not Complexity Metrics Alone?

Research on AI task automation (2025) shows that **autonomy correlates with specification clarity**, not with apparent complexity:

- A "simple" 20-line bug fix is **COMPLEX** if reproduction is unclear
- A "complex" multi-file refactoring is **SIMPLE** if it's "extract method across N files" with deterministic tests
- Time constraints favor **heuristic-based decisions over learned models** (user won't wait 10s for router inference)

**Reference:** [Heuristics in Managing Complex Decision Tasks](https://www.tandfonline.com/doi/full/10.1080/0144929X.2025.2587732) — Under time pressure, simple heuristics outperform complex learned models.

---

## 3. Multi-Model Orchestration Patterns in Practice

### 2026 Orchestration Ecosystem

**Leading patterns:**

1. **LangGraph / LangChain stack** (most common in 2025-2026)
   - LangChain: foundational library for multi-model apps
   - LangGraph: orchestrates multi-agent workflows with state machines
   - LangServe: real-time deployment
   - Enables dynamic model selection per task step

2. **Microsoft AutoGen** (multi-agent specialist)
   - Conversation-based coordination between agents
   - Explicit agent roles (planner, executor, reviewer)
   - Built for teams of agents with different capabilities

3. **Specialized routing frameworks** (emerging 2025-2026)
   - Semantic routing: "which model understands this domain best?"
   - Rule-based pre-routing: signals before inference
   - Cost-optimized routing: small models for low-stakes tasks, large models for critical paths

### Claude Code + Codex Integration Patterns

Recent 2025-2026 projects document **effective dual-tool patterns**:

**Vision-Driven Parallel Execution:**
- Shared "vision file" (REQUIREMENTS.md or PLAN.md) keeps both tools aligned
- Implementation file updated by both tools with explicit handoff points
- Worklog captures dependency issues to prevent redundant work
- Each tool reads state from shared files, not through API calls

**Orchestration Model:**
```
Claude Code (orchestrator):
  ├─ Plans overall architecture
  ├─ Identifies task boundary
  ├─ Creates worktree for Codex
  ├─ Hands off with explicit task spec
  └─ Reviews + merges Codex output

Codex (executor in parallel worktree):
  ├─ Reads task spec from PLAN.md
  ├─ Executes with `codex --full-auto "task"`
  ├─ Writes to isolated branch
  └─ Signals completion
```

**Why this works:**
- Eliminates context-rot (each tool reads fresh state, not memory)
- Enables true parallelism (no blocking on tool-to-tool calls)
- Clear handoff points (reduces re-explaining work)
- Auditable (all decisions logged in .planning/)

**Reference:** [LLM Orchestration in 2026](https://research.aimultiple.com/llm-orchestration/) — Top frameworks emphasize **state machines with explicit transitions** over implicit agent autonomy.

---

## 4. Git Worktree Management for Parallel AI Execution

### Worktree Fundamentals

**What worktrees enable:**
- Each branch checked out in **separate directory** simultaneously
- Shared Git object database (history, reflog, config)
- **True isolation:** changes in worktree A don't affect worktree B until merged
- Faster than stash/branch-switch cycle

**Key commands:**
```bash
# Create worktree
git worktree add ./worktrees/task-branch branch-name

# List active worktrees
git worktree list

# Move worktree
git worktree move ./worktrees/task-branch ./new/location

# Remove (after merge)
git worktree remove ./worktrees/task-branch

# Lock (for removable media)
git worktree lock ./worktrees/task-branch

# Prune stale metadata
git worktree prune
```

### Parallel AI Execution Workflow

**Recommended pattern for gsd-multi-model:**

```
Main worktree (Claude Code orchestrator):
  ├─ on: main branch
  ├─ role: planning, architecture, review
  └─ state: reads .planning/STATE.md

Parallel worktree (Codex executor):
  ├─ on: task-specific branch
  ├─ created by: git worktree add ./worktrees/codex-task-123 codex/task-123
  ├─ role: autonomous execution
  └─ merges back to: task-123 → main (via PR/review)
```

**Isolation benefits:**
- Codex works uninterrupted in isolated directory
- Claude Code can continue planning/reviewing in main worktree
- No branch switching overhead
- Failed Codex execution doesn't block main tree

### Merge-Back Strategy

**Safe merge pattern (2025 best practice):**

1. **Selective merge** (not all-or-nothing):
   ```bash
   # In main worktree, after Codex completes:
   git merge codex/task-123 --no-commit
   # Review changes before final commit
   ```

2. **Conflict resolution strategy:**
   - Use "Rebase Before PR" model: ensure Codex branch built on latest main
   - Minimize merge conflicts by keeping task boundaries clean
   - For conflicts: choose which version to keep based on architecture decision

3. **Verification step** (critical):
   - After merge, run full test suite before pushing
   - Cross-review: Claude verifies Codex output, vice versa

**Reference:** [Git Worktree Tutorial](https://www.datacamp.com/tutorial/git-worktree-tutorial) + [Concurrent Development Best Practices](https://www.kenmuse.com/blog/using-git-worktrees-for-concurrent-development/) — Worktrees transform parallel development from "context-switch headache" to "true isolation."

### Worktree Limitations to Know

- **Submodules:** Git documents multiple checkout as "experimental" due to submodule issues — avoid worktrees if project uses submodules
- **Prune strategy:** Git automatically prunes missing worktrees after 3 months; use `git worktree lock` for long-lived worktrees
- **Branch checkout:** Each branch can only be checked out in ONE worktree at a time; trying to check out same branch twice will fail

---

## 5. Cross-Model Verification Patterns

### Why Different Models Need Different Review Roles

**2025 research finding:** Different AI models have different strengths for different verification tasks:
- Claude Sonnet 3.7: **superior at long-context consistency**, architectural pattern maintenance
- OpenAI o4-mini: **excellent at formal reasoning**, code verifiability checking
- DeepSeek R1: **strong at advanced code reasoning** (reinforcement learned)

**Implication:** Don't use one model to review another; use **specialized models for verification** of different aspects.

### Cross-Model Review Strategy for gsd-multi-model

**Recommended pattern:**

```
Claude Code generates architecture/multi-file changes:
  ├─ Reviews for:
  │  ├─ Consistency with Codex output (no conflicts)
  │  ├─ Architectural coherence
  │  └─ Missing edge cases
  └─ Tool: Codex's verification capability

Codex generates tests/implementations:
  ├─ Reviews for:
  │  ├─ Correctness against Claude's architecture
  │  ├─ Test coverage of edge cases
  │  └─ Code quality issues
  └─ Tool: Claude's architectural reasoning
```

### Verification Techniques (2025 consensus)

1. **Prompt Engineering** (most portable across models)
   - Optimize input prompts to "achieve better and more secure outputs"
   - Model-agnostic: works with any LLM
   - Fast (no additional inference rounds needed)

2. **Tool Integration** (hybrid approach)
   - Combine LLM output with traditional verification (linters, type checkers, unit tests)
   - Layered defense: LLM output + deterministic verification
   - Example: Claude Code generates types, TypeScript compiler verifies them

3. **Retrieval-Augmented Generation (RAG)**
   - Query external knowledge base to improve context
   - Applies to any model, improves accuracy
   - Useful for reviewing against architectural guidelines

4. **Agentic Verification** (emerging 2025 pattern)
   - Verification agent automatically generates targeted tests
   - Runs unit + integration tests for changed code
   - Tests become part of PR checks (automated validation)

### Verification Doesn't Mean "Check Everything"

**Critical insight from 2025 research:** Effective verification requires **specialization**:
- Don't have one reviewer check all aspects
- Different aspects need different cognitive tools
- Example: test verification needs different reasoning than architectural review

**Reference:** [Dual Perspective Review on LLMs and Code Verification](https://www.frontiersin.org/journals/computer-science/articles/10.3389/fcomp.2025.1655469/full) — "Effective verification combines multiple strategies rather than relying on a single approach."

---

## 6. Existing AI Task Routing Approaches in the Wild

### What's Already Working (2025-2026)

1. **LangChain/LangGraph approach** (most documented)
   - Define task as graph nodes (orchestration layer)
   - Each node specifies which model(s) run
   - Conditional routing based on node output
   - Advantage: explicit, debuggable, auditable

2. **Claude Code + Codex projects** (from real examples)
   - Vision file (shared REQUIREMENTS) as single source of truth
   - Implementation file tracks progress (both tools can update)
   - Worklog captures decisions to prevent re-work
   - Works because state is **written down**, not memorized

3. **Specialized agent frameworks** (AutoGen, Ruflo, etc.)
   - Agent coordinator role (decides which agent does what)
   - Explicit agent capabilities (what each agent is good at)
   - Conversation-based negotiation (agents discuss who should do task)
   - More flexible but less deterministic than rule-based

### Why Simple Heuristics Beat Learned Routing

**2026 consensus from industry:** For development workflows, **simple, transparent heuristics win over learned models** because:

1. **Speed:** No inference latency for routing decision (heuristics = instant)
2. **Interpretability:** Developers understand why task routed to which tool
3. **Reliability:** Heuristics don't hallucinate or misclassify edge cases
4. **Tuning:** Easy to adjust rules based on experience

**Reference:** [Why 2026 Is the Year of Multi-Model Routing](https://medium.com/@MateCloud/why-2026-is-the-year-of-multi-model-routing-technical-challenges-and-system-design-2457dcdd2209) — "Rule-based approaches are predictable, transparent, and fast to execute, making them an excellent choice for well-defined, simple workflows."

---

## 7. Implementation Recommendations for gsd-multi-model

### Task Splitting Heuristic (Ready to Implement)

**Location:** `.planning/PLAN.md` generation in `/gsd:plan-phase`

**Algorithm:**
```
For each planned task:

1. PARSE signals from task description
   - files_affected = count of files touched
   - has_test_cases = has clear test cases in description
   - is_isolated = doesn't affect public APIs
   - clear_success_criteria = description has "definition of done"

2. CLASSIFY:
   - If files_affected > 3: → flag COMPLEX
   - If NOT has_test_cases AND files_affected > 1: → flag COMPLEX
   - If NOT is_isolated: → flag COMPLEX
   - If NOT clear_success_criteria: → flag COMPLEX

3. ROUTE:
   - COUNT complexity flags
   - If 0 flags: → route to CODEX (autonomous)
   - If 1+ flags: → route to CLAUDE CODE (interactive)

4. PRESENT to user:
   - Show routing decision
   - Allow override (user knows edge cases)
   - Log decision to .planning/PLAN.md
```

### Worktree Management (Ready to Implement)

**Location:** Bash helper scripts in `skills/` or `global/`

**Script outline:**
```bash
#!/bin/bash
# create-codex-worktree.sh

TASK_ID=$1
BRANCH_NAME="codex/task-${TASK_ID}"
WORKTREE_PATH="./worktrees/${BRANCH_NAME}"

# Create new branch from main
git checkout main
git pull
git checkout -b "${BRANCH_NAME}"

# Create worktree
git worktree add "${WORKTREE_PATH}" "${BRANCH_NAME}"

# Run codex in worktree
cd "${WORKTREE_PATH}"
codex --full-auto "$(cat ../../.planning/PLAN.md | grep -A20 "Task ${TASK_ID}")"

# Signal completion, return to main
cd ../..
echo "Task ${TASK_ID} completed in ${WORKTREE_PATH}"
```

### Cross-Model Review Integration (Ready to Implement)

**Location:** `/gsd-codex-verify` skill (already exists)

**Enhancement:** After Codex execution in worktree:
1. Claude Code reads Codex output (in isolated worktree)
2. Runs verification checklist:
   - [ ] Tests pass
   - [ ] Doesn't break other tests
   - [ ] Consistent with Claude's architecture decisions
   - [ ] No obvious code quality issues
3. Codex (if available) verifies Claude's architecture decisions
4. Both pass OR task kicked back for fixes

---

## 8. Architecture for gsd-multi-model Task Splitting

### System Components

```
.planning/ (single source of truth)
├─ STATE.md (current phase position)
├─ PROJECT.md (product vision)
├─ REQUIREMENTS.md (deliverables)
├─ PLAN.md (XML task list with routing)
└─ research/ (domain research)

/gsd:plan-phase (Claude Code)
├─ Reads REQUIREMENTS.md
├─ Generates task list in PLAN.md
├─ Applies task-splitting heuristic
├─ Annotates each task: CODEX or CLAUDE
└─ Present to user for override

/gsd:execute-phase (parallel)
├─ Claude Code (main worktree)
│  ├─ Complex tasks (architecture, multi-file)
│  ├─ Coordination role
│  └─ Reviews Codex output
│
└─ Codex (parallel worktree)
   ├─ Autonomous tasks (CRUD, tests, scripts)
   ├─ Isolated from Claude tree
   └─ Signals completion via git commit

/gsd-codex-verify (cross-review)
├─ Claude verifies Codex output
└─ Codex verifies Claude output

git worktrees (parallel execution)
├─ main/ (Claude Code orchestrator)
└─ worktrees/codex-task-N/ (Codex executor)
```

### State Management

**Key insight:** Use .planning/ files as **shared state**, not internal memory:

- PLAN.md: source of truth for what's being built, who's building it, what signals routed the decision
- Codex reads PLAN.md to know its task
- Claude reads PLAN.md to know what Codex should do
- Cross-review reads both output + PLAN.md to verify consistency

**Benefit:** No "re-explaining" — each tool reads fresh state on each invocation.

---

## 9. Confidence Assessment

| Area | Confidence | Reasoning |
|------|------------|-----------|
| **Task complexity signals** | HIGH | Multiple 2025-2026 sources agree on rule-based heuristics; signals derived from workflow automation industry standards |
| **Multi-model routing patterns** | HIGH | LangGraph, AutoGen, Medium analysis all converge on state-machine + explicit routing; not speculative |
| **Git worktree best practices** | MEDIUM-HIGH | Recent 2025-2026 articles on AI + worktrees; limitation with submodules is documented in official Git docs |
| **Cross-model verification** | MEDIUM | 2025 research identifies strategies (prompt engineering, tool integration, RAG); model-specific strengths emerging but not yet standardized |
| **Claude Code + Codex patterns** | MEDIUM | Documented in recent blog posts + GitHub projects; less academic rigor than other areas, but consistent across examples |
| **Implementation readiness** | HIGH | Heuristic algorithm, worktree scripts, verification checklist can be implemented immediately |

---

## 10. Gaps & Phase-Specific Research Flags

### Areas of Uncertainty

1. **LLM-based fallback router** — When should user be asked to decide vs. auto-routing?
   - Recommend: Phase 2 (execute) can test heuristic, gather feedback on edge cases
   - Then train lightweight classifier if needed

2. **Codex `--full-auto` behavior** — Exact limits of fully autonomous execution
   - Need: real testing with various task types in Phase 2
   - Risk: Codex may request human input, blocking parallel execution

3. **Cross-model review effectiveness** — Does Claude actually catch Codex bugs well?
   - Need: benchmark in Phase 2 (generate test cases, intentionally break Codex output, see if Claude catches it)
   - This will inform whether verification is sufficient or needs additional tools

4. **Worktree merge conflicts at scale** — Does heuristic really prevent merge conflicts?
   - Need: stress test with large codebases in Phase 3
   - Risk: Complex refactorings in Claude + Codex could still conflict

### Research Flags by Phase

| Phase | Topic | Flag | Research Approach |
|-------|-------|------|-------------------|
| 2 (execute) | Heuristic quality | Test on 5-10 real tasks, measure false positives/negatives | A/B test: auto-routed vs. manual routing |
| 2 (execute) | Codex autonomy limits | What % of tasks complete without human intervention? | Monitor `codex --full-auto` for request-human-input |
| 2 (execute) | Verification effectiveness | Do Claude reviews actually catch Codex bugs? | Intentional test: insert bugs, measure catch rate |
| 3 (scale) | Merge conflicts | Heuristic isolation prevents conflicts? | Large refactoring task, measure merge conflict count |
| 3 (scale) | Worktree overhead | Is worktree creation/cleanup overhead acceptable? | Benchmark: time/disk space for 100 parallel tasks |

---

## 11. Sources

### Multi-Model Routing & Orchestration
- [Why 2026 Is the Year of Multi-Model Routing: Technical Challenges and System Design](https://medium.com/@MateCloud/why-2026-is-the-year-of-multi-model-routing-technical-challenges-and-system-design-2457dcdd2209) — MateCloud, Dec 2025
- [LLM Orchestration in 2026: Top 22 frameworks and gateways](https://research.aimultiple.com/llm-orchestration/) — AI Multiple, 2026
- [Why You Should Use AI Model Orchestration Tools (And Which Ones) In 2026](https://www.prompts.ai/en/blog/why-use-ai-model-orchestration-tools-2026) — Prompts.ai, 2026
- [The 4 best AI orchestration tools in 2026](https://zapier.com/blog/ai-orchestration-tools/) — Zapier, 2026

### Task Complexity & Heuristics
- [Heuristics in Managing Complex Clinical Decision Tasks in Experts' Decision Making](https://pmc.ncbi.nlm.nih.gov/articles/PMC4891069/) — PMC, academic research
- [Under pressure: how time constraints, task complexity, and AI reliability shape human-AI interaction](https://www.tandfonline.com/doi/full/10.1080/0144929X.2025.2587732) — 2025 empirical research
- [Fast or Frugal, but Not Both: Decision Heuristics Under Time Pressure](https://pmc.ncbi.nlm.nih.gov/articles/PMC5708146/) — PMC, decision science

### Git Worktrees & Parallel Development
- [Using Git Worktrees for Concurrent Development](https://www.kenmuse.com/blog/using-git-worktrees-for-concurrent-development/) — Ken Muse, 2025
- [Git Worktree Tutorial: Work on Multiple Branches Without Switching](https://www.datacamp.com/tutorial/git-worktree-tutorial) — DataCamp, tutorial
- [How to Leverage Git Trees for Parallel Agent Workflows](https://elchemista.com/en/post/how-to-leverage-git-trees-for-parallel-agent-workflows) — elchemista, 2025

### Code Generation & AI Model Comparison
- [Comparing AI models for code generation](https://www.graphite.com/guides/ai-coding-model-comparison) — Graphite, 2026
- [AI Code Generation Benchmarks: Accuracy and Speed Tested](https://zencoder.ai/blog/ai-code-generation-benchmarks) — ZenCoder, 2025
- [Testing AI coding agents (2025): Cursor vs. Claude, OpenAI, and Gemini](https://render.com/blog/ai-coding-agents-benchmark) — Render, 2025

### Verification Strategies
- [A dual perspective review on large language models and code verification](https://www.frontiersin.org/journals/computer-science/articles/10.3389/fcomp.2025.1655469/full) — Frontiers, 2025
- [How CodeRabbit's agentic code validation helps with code reviews](https://www.coderabbit.ai/blog/how-coderabbits-agentic-code-validation-helps-with-code-reviews) — CodeRabbit, 2025
- [Top 5 AI code review tools in 2025](https://blog.logrocket.com/ai-code-review-tools-2025/) — LogRocket, 2025

### Agent Workflows & Routing
- [Agentic AI: A Comprehensive Survey of Architectures, Applications, and Future Directions](https://arxiv.org/html/2510.25445v1) — arXiv, academic survey 2025
- [Agentic AI Trends for 2026: What Will Work (with Examples)](https://www.ema.co/additional-blogs/addition-blogs/agentic-ai-trends-predictions-2025) — EMA, 2025
- [What Are Agentic Workflows? Patterns, Memory, Use Cases, and Examples](https://weaviate.io/blog/what-are-agentic-workflows) — Weaviate, 2025
- [Agents vs. Workflows: The Framework Founders Actually Need](https://medium.com/fika-ventures/agents-vs-workflows-the-framework-founders-actually-need-519b5da8bd34) — Fika Ventures, Feb 2026

### Claude Code & Codex Integration
- [Building AI-driven workflows powered by Claude Code and other tools](https://uxdesign.cc/designing-with-claude-code-and-codex-cli-building-ai-driven-workflows-powered-by-code-connect-ui-f10c136ec11f) — UX Collective, 2025
- [Codex CLI × Claude Code: 3x Productivity with Parallel Workflow Integration](https://smartscope.blog/en/ai-development/practices/codex-claude-code-workflow-integration/) — SmartScope, 2025

### Task Type Classification
- [Code refactoring](https://en.wikipedia.org/wiki/Code_refactoring) — Wikipedia
- [It's Not a Bug, It's a Feature: How Misclassification Impacts Bug Prediction](https://www.microsoft.com/en-us/research/wp-content/uploads/2013/05/icse2013-bugclassify.pdf) — Microsoft Research, academic
- [Detecting refactoring type of software commit messages based on ensemble machine learning algorithms](https://www.nature.com/articles/s41598-024-72307-0) — Nature Scientific Reports, 2024

---

## 12. Actionable Next Steps

### For Phase 2 (Execute - gsd-multi-model implementation):

1. **Implement task-splitting heuristic** (Section 2)
   - Add to `/gsd:plan-phase` logic
   - Test on 5-10 real tasks from GSD projects
   - Measure routing accuracy

2. **Create worktree management helpers** (Section 4)
   - Bash scripts: create, execute, merge, cleanup
   - Integrate with `/gsd:execute-phase`
   - Test with Codex `--full-auto` execution

3. **Enhance cross-model verification** (Section 5)
   - Checklist for Claude reviewing Codex output
   - Checklist for Codex reviewing Claude output
   - Automated test generation for verification

4. **Real-world testing**
   - Run gsd-multi-model on an actual project (e.g., this repo)
   - Measure: parallelism gains, verification effectiveness, merge conflicts
   - Iterate on heuristic based on edge cases

### Research Validation Milestones:

- **Milestone 1:** Heuristic accuracy > 80% (false positive rate < 15%)
- **Milestone 2:** Codex autonomy rate > 85% (completes without human intervention)
- **Milestone 3:** Cross-review catches > 70% of seeded bugs in test tasks
- **Milestone 4:** Worktree merge success rate > 95% (< 5% manual conflict resolution)

---

## End of Research

This document should feed directly into:
- **ROADMAP.md:** Phase structure, ordering of implementation tasks
- **REQUIREMENTS.md:** Specific deliverables for heuristic, worktree management, verification
- **/gsd:plan-phase:** Task routing logic implementation
- **Testing strategy:** Benchmark plans for cross-review effectiveness, heuristic accuracy

**Next:** Use findings to create REQUIREMENTS.md (what to build) and ROADMAP.md (how to build it, in what phases).
