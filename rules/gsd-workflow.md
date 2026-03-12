When working on this project, follow the GSD dual-tool workflow:
1. Check /gsd:status before making changes
2. If .planning/STATE.md exists, respect the current phase position
3. During execution, handle complex/interactive tasks -- suggest autonomous tasks for Codex
4. Each task must produce an atomic, revertable git commit
5. After execution, run /gsd-multi:codex-verify for cross-review (each tool reviews the other's work)
