import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { parseStateFile, parseRoadmapFile } from './state-parser.js';
import type { GsdAction, RunnerConfig } from './types.js';

/**
 * Determine the next GSD action based on disk state.
 *
 * Handles the full lifecycle:
 *   1. No .planning/PROJECT.md    → init-project (runs full new-project --auto flow)
 *   2. Has ROADMAP.md + STATE.md  → plan/execute/verify (original logic)
 *
 * The new-project workflow handles research, requirements, and roadmap
 * creation in a single session, so no intermediate bootstrap states needed.
 *
 * Pure-ish function: only side effect is file reads.
 */
export function determineNextAction(projectDir: string, config?: RunnerConfig): GsdAction {
  const planningDir = join(projectDir, '.planning');
  const continueHerePath = join(planningDir, '.continue-here.md');
  const projectPath = join(planningDir, 'PROJECT.md');
  const statePath = join(planningDir, 'STATE.md');
  const roadmapPath = join(planningDir, 'ROADMAP.md');

  // 0. Check for continue-here file (resume takes priority)
  if (existsSync(continueHerePath)) {
    return { type: 'resume' };
  }

  // 1. No PROJECT.md → need to initialize (new-project creates everything)
  if (!existsSync(projectPath)) {
    const brief = config?.projectBrief;
    if (!brief) {
      return { type: 'error', reason: 'No .planning/PROJECT.md and no PROJECT_BRIEF provided. Set PROJECT_BRIEF or PROJECT_BRIEF_FILE to bootstrap a new project.' };
    }
    return { type: 'init-project', brief };
  }

  // 2. PROJECT.md exists but no ROADMAP/STATE yet
  //    This means new-project was interrupted partway through.
  //    Re-run init to complete the flow.
  if (!existsSync(roadmapPath) || !existsSync(statePath)) {
    const brief = config?.projectBrief;
    if (!brief) {
      return { type: 'error', reason: '.planning/PROJECT.md exists but ROADMAP.md or STATE.md missing. Set PROJECT_BRIEF to re-run initialization.' };
    }
    return { type: 'init-project', brief };
  }

  // 3. Existing phase logic (original)
  let stateContent: string;
  try {
    stateContent = readFileSync(statePath, 'utf-8');
  } catch {
    return { type: 'error', reason: 'STATE.md not found or unreadable' };
  }

  const state = parseStateFile(stateContent);

  if (state.currentPhase === 0 && state.totalPhases === 0) {
    return { type: 'error', reason: 'STATE.md could not be parsed' };
  }

  let roadmapContent: string;
  try {
    roadmapContent = readFileSync(roadmapPath, 'utf-8');
  } catch {
    roadmapContent = '';
  }

  const roadmap = parseRoadmapFile(roadmapContent);

  if (roadmap.length > 0 && roadmap.every((p) => p.complete)) {
    return { type: 'done' };
  }

  const phaseNumber = state.currentPhase;

  if (state.status.toLowerCase().includes('ready to plan') || state.plansInPhase === 0) {
    return { type: 'plan', phase: phaseNumber };
  }

  if (state.plansComplete < state.plansInPhase) {
    return { type: 'execute', phase: phaseNumber };
  }

  if (state.plansComplete === state.plansInPhase && state.plansInPhase > 0) {
    return { type: 'verify', phase: phaseNumber };
  }

  return { type: 'error', reason: 'Could not determine next action' };
}
