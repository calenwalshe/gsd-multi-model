import { loadConfig } from './config.js';
import { determineNextAction } from './state-machine.js';
import { runGsdCommand, type SessionResult } from './session-runner.js';
import { expandActionPrompt } from './prompt-expander.js';
import type { GsdAction, Notifier, RunnerConfig } from './types.js';
import { logger } from './logger.js';
import { createNotifier } from './notifier.js';
import { TelegramNotifier } from './telegram.js';
import { StuckDetector } from './stuck-detector.js';
import { checkCodexAvailable, runExecuteWithRouting } from './executor-router.js';

// --- SIGTERM state ---
let isShuttingDown = false;
let currentController: AbortController = new AbortController();

/** Reset shutdown state (for testing only). */
export function _resetShutdownState(): void {
  isShuttingDown = false;
}

process.on('SIGTERM', () => {
  if (isShuttingDown) return;
  isShuttingDown = true;
  logger.loop.info('SIGTERM received, completing current operation...');
  currentController.abort();
});

/**
 * Map a GsdAction to a fully expanded prompt.
 * Reads GSD command files, resolves @ references, inlines all context.
 * Throws for done/error actions which should not be mapped.
 */
export function actionToPrompt(action: GsdAction): string {
  switch (action.type) {
    case 'init-project': {
      const { prompt } = expandActionPrompt('init-project', { brief: action.brief });
      return prompt;
    }
    case 'plan': {
      const { prompt } = expandActionPrompt('plan', { phase: action.phase });
      return prompt;
    }
    case 'execute': {
      const { prompt } = expandActionPrompt('execute', { phase: action.phase });
      return prompt;
    }
    case 'verify': {
      const { prompt } = expandActionPrompt('verify');
      return prompt;
    }
    case 'resume': {
      const { prompt } = expandActionPrompt('resume');
      return prompt;
    }
    case 'done':
      throw new Error('Cannot convert done action to prompt');
    case 'error':
      throw new Error(`Cannot convert error action to prompt: ${action.reason}`);
  }
}

/**
 * Run a checkpoint (pause-work) session to save context before
 * continuing with a fresh session.
 */
async function runCheckpointReal(config: RunnerConfig): Promise<void> {
  logger.loop.info('Running checkpoint (pause-work)...');
  const controller = new AbortController();
  await runGsdCommand('/gsd:pause-work', config, controller);
  logger.loop.info('Checkpoint complete');
}

export interface LoopDeps {
  determineNextAction: (projectDir: string, config?: RunnerConfig) => GsdAction;
  runGsdCommand: (prompt: string, config: RunnerConfig, controller: AbortController, stuckDetector?: StuckDetector) => Promise<SessionResult>;
  runCheckpoint: (config: RunnerConfig) => Promise<void>;
  notifier?: Notifier;
  stuckDetector?: StuckDetector;
}

/**
 * Main daemon loop. Cycles through:
 *   determineNextAction -> actionToPrompt -> runGsdCommand -> check threshold -> repeat
 *
 * Re-reads disk state before every iteration (no in-memory GSD state).
 * Handles compaction threshold by running pause-work checkpoint.
 * Exits on done/error actions.
 *
 * @param config - Runner configuration
 * @param deps - Optional dependency injection for testing
 * @param onShutdownHook - Optional callback to register a shutdown trigger (for testing)
 */
export async function runLoop(
  config: RunnerConfig,
  deps?: Partial<LoopDeps>,
  onShutdownHook?: (triggerShutdown: () => void) => void,
): Promise<void> {
  const nextAction = deps?.determineNextAction ?? determineNextAction;
  const execCommand = deps?.runGsdCommand ?? runGsdCommand;
  const checkpoint = deps?.runCheckpoint ?? runCheckpointReal;
  const notifier = deps?.notifier;
  const stuckDetector = deps?.stuckDetector;

  // Allow tests to register a shutdown trigger
  if (onShutdownHook) {
    onShutdownHook(() => { isShuttingDown = true; });
  }

  while (true) {
    // Re-read disk state before every decision
    const action = nextAction(config.projectDir, config);

    if (action.type === 'done') {
      logger.loop.info('All phases complete. Exiting.');
      return;
    }

    if (action.type === 'error') {
      logger.loop.error({ reason: action.reason }, 'State machine returned error');
      throw new Error(action.reason);
    }

    // Gate approval at verify steps
    if (action.type === 'verify' && notifier) {
      const approved = await notifier.requestGateApproval(
        `Phase ${action.phase} ready for verification. Approve to continue, reject to halt.`,
      );
      if (!approved) {
        logger.gate.info({ phase: action.phase }, 'Gate rejected by user, halting loop');
        return;
      }
      logger.gate.info({ phase: action.phase }, 'Gate approved by user');
    }

    // Multi-model routing: execute action dispatches to Codex batch + Claude sequentially
    if (action.type === 'execute' && config.codexEnabled) {
      await notifier?.sendProgress(`Starting: execute phase ${action.phase} (multi-model routing)`);
      await runExecuteWithRouting(action.phase, config, execCommand, notifier);
      await notifier?.sendProgress(`Completed: execute phase ${action.phase}`);
      // Check shutdown, skip to next iteration
      if (isShuttingDown) {
        logger.loop.info('Shutdown requested, running final checkpoint...');
        await checkpoint(config);
        return;
      }
      continue;
    }

    const prompt = actionToPrompt(action);
    logger.loop.info({ action: action.type, prompt }, 'Executing action');

    // Build human-readable label for notifications
    const phaseLabel = 'phase' in action ? ` phase ${action.phase}` : '';

    // Send progress notification
    await notifier?.sendProgress(`Starting: ${action.type}${phaseLabel}`);

    // Create fresh controller for this iteration
    currentController = new AbortController();
    const result = await execCommand(prompt, config, currentController, stuckDetector);

    // Handle stuck detection
    if (result.stuck) {
      logger.loop.error({ sessionId: result.sessionId }, 'Session aborted due to stuck agent');
      await notifier?.sendAlert(`Stuck agent detected in session ${result.sessionId}. Halting.`);
      return;
    }

    logger.loop.info(
      { sessionId: result.sessionId, success: result.success, costUsd: result.costUsd },
      'Session complete',
    );

    // Send completion notification
    await notifier?.sendProgress(`Completed: ${action.type}${phaseLabel} (cost: $${result.costUsd.toFixed(2)})`);

    // Check compaction threshold
    if (result.thresholdHit) {
      logger.loop.warn('Compaction threshold hit, running checkpoint...');
      await checkpoint(config);
    }

    // Check shutdown flag
    if (isShuttingDown) {
      logger.loop.info('Shutdown requested, running final checkpoint...');
      await checkpoint(config);
      return;
    }
  }
}

/**
 * Entry point: load config and run the daemon loop.
 */
export async function main(): Promise<void> {
  const config = loadConfig();

  // Check Codex availability once at startup (per CONTEXT.md decisions)
  const codexCliAvailable = checkCodexAvailable();
  config.codexEnabled = config.codexEnabled && codexCliAvailable;

  logger.loop.info(
    { projectDir: config.projectDir, maxTurns: config.maxTurns, compactionThreshold: config.compactionThreshold },
    'GSD Runner starting',
  );

  // Initialize optional notifier (Telegram or GChat)
  const notifier = createNotifier(config, logger);
  if (notifier) {
    if (notifier instanceof TelegramNotifier) {
      (notifier as TelegramNotifier & { start(): void }).start();
    }
    notifier.startHeartbeat();
    logger.loop.info({ notifierType: notifier.constructor.name }, 'Notifier started with heartbeat');
  }

  if (!config.codexEnabled) {
    await notifier?.sendAlert('Codex not available or CODEX_ENABLED=false. Running Claude-only.');
    logger.loop.info('Codex disabled — running Claude-only mode');
  } else {
    logger.loop.info('Codex available — multi-model routing enabled');
  }

  // Initialize stuck detector
  const stuckDetector = new StuckDetector(config.stuckDetector);

  try {
    await runLoop(config, { notifier, stuckDetector });
  } finally {
    if (notifier) {
      await notifier.stop();
      logger.loop.info('Notifier stopped');
    }
  }

  logger.loop.info('GSD Runner completed successfully');
  process.exit(0);
}

// Auto-run only when executed directly (not imported as module)
const isDirectRun = process.argv[1] && (
  process.argv[1].endsWith('/index.ts') ||
  process.argv[1].endsWith('/index.js')
);

if (isDirectRun) {
  main().catch((err) => {
    logger.loop.fatal({ err }, 'GSD Runner failed');
    process.exit(1);
  });
}
