import { z } from 'zod';
import type { ParsedState, PhaseInfo } from './types.js';

const StateSchema = z.object({
  currentPhase: z.number().min(0),
  totalPhases: z.number().min(0),
  plansInPhase: z.number().min(0),
  plansComplete: z.number().min(0),
  status: z.string(),
});

const DEFAULT_STATE: ParsedState = {
  currentPhase: 0,
  totalPhases: 0,
  plansInPhase: 0,
  plansComplete: 0,
  status: 'unknown',
};

/**
 * Parse STATE.md content into a typed ParsedState structure.
 * Returns sensible defaults for malformed or empty input (never throws).
 */
export function parseStateFile(content: string): ParsedState {
  try {
    const phaseMatch = content.match(/Phase:\s*(\d+)\s*of\s*(\d+)/);
    const planMatch = content.match(/Plan:\s*(\d+)\s*of\s*(\d+)/);
    const statusMatch = content.match(/Status:\s*(.+)/);

    const raw = {
      currentPhase: phaseMatch ? parseInt(phaseMatch[1], 10) : 0,
      totalPhases: phaseMatch ? parseInt(phaseMatch[2], 10) : 0,
      plansComplete: planMatch ? parseInt(planMatch[1], 10) : 0,
      plansInPhase: planMatch ? parseInt(planMatch[2], 10) : 0,
      status: statusMatch?.[1]?.trim() ?? 'unknown',
    };

    return StateSchema.parse(raw);
  } catch {
    return DEFAULT_STATE;
  }
}

/**
 * Parse ROADMAP.md content into a list of PhaseInfo entries.
 * Returns empty array for malformed input (never throws).
 */
export function parseRoadmapFile(content: string): PhaseInfo[] {
  try {
    const phases: PhaseInfo[] = [];
    const phaseRegex = /- \[([ x])\] \*\*Phase (\d+): (.+?)\*\*/g;
    let match;

    while ((match = phaseRegex.exec(content)) !== null) {
      phases.push({
        number: parseInt(match[2], 10),
        name: match[3],
        complete: match[1] === 'x',
      });
    }

    return phases;
  } catch {
    return [];
  }
}
