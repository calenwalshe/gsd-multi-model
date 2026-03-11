import type { StuckDetectorConfig } from './types.js';

const READ_ONLY_TOOLS = new Set(['Read', 'Glob', 'Grep', 'WebFetch']);

/**
 * Simple djb2 hash for string comparison (not cryptographic).
 */
function djb2(str: string): number {
  let hash = 5381;
  for (let i = 0; i < str.length; i++) {
    hash = ((hash << 5) + hash + str.charCodeAt(i)) | 0;
  }
  return hash;
}

/**
 * Sliding window tool call tracker that detects stuck/looping agents.
 * Records tool calls and returns true when the same tool+args combination
 * appears more times than the configured threshold within the window.
 */
export class StuckDetector {
  private window: number[] = [];
  private readonly config: StuckDetectorConfig;

  constructor(config: StuckDetectorConfig) {
    this.config = config;
  }

  /**
   * Record a tool call. Returns true if the agent appears stuck.
   */
  record(toolName: string, args: string): boolean {
    const hash = djb2(`${toolName}:${args}`);

    // Evict oldest if window is full
    if (this.window.length >= this.config.windowSize) {
      this.window.shift();
    }
    this.window.push(hash);

    // Count occurrences of this hash in window
    let count = 0;
    for (const h of this.window) {
      if (h === hash) count++;
    }

    const threshold = READ_ONLY_TOOLS.has(toolName)
      ? this.config.threshold * this.config.readOnlyMultiplier
      : this.config.threshold;

    return count >= threshold;
  }

  /**
   * Clear the sliding window.
   */
  reset(): void {
    this.window = [];
  }
}
