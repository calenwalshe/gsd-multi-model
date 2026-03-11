import { query } from '@anthropic-ai/claude-agent-sdk';
import { RunnerConfig } from './types.js';
import { logger } from './logger.js';
import { StuckDetector } from './stuck-detector.js';

export interface SessionResult {
  success: boolean;
  sessionId: string;
  compactionCount: number;
  thresholdHit: boolean;
  costUsd: number;
  resultSubtype: string;
  stuck: boolean;
}

/**
 * Run a GSD command via the Agent SDK query() function.
 *
 * Wraps query() with bounded sessions, in-stream compaction tracking,
 * stuck agent detection, and graceful abort support via AbortController.
 */
export async function runGsdCommand(
  prompt: string,
  config: RunnerConfig,
  controller: AbortController,
  stuckDetector?: StuckDetector,
): Promise<SessionResult> {
  logger.session.info({ prompt: prompt.slice(0, 100), maxTurns: config.maxTurns }, 'Starting session');

  // Reset stuck detector for fresh session
  stuckDetector?.reset();

  const stream = query({
    prompt,
    options: {
      cwd: config.projectDir,
      maxTurns: config.maxTurns,
      maxBudgetUsd: config.maxBudgetUsd,
      permissionMode: 'bypassPermissions',
      allowDangerouslySkipPermissions: true,
      systemPrompt: { type: 'preset', preset: 'claude_code' },
      settingSources: ['user', 'project'],
      abortController: controller,
    },
  });

  let sessionId = '';
  let compactionCount = 0;
  let resultMessage: Record<string, unknown> | null = null;

  for await (const message of stream) {
    const msg = message as Record<string, unknown>;

    // Capture session ID from init message
    if (msg.type === 'system' && msg.subtype === 'init') {
      sessionId = (msg.session_id as string) ?? '';
      logger.session.info({ sessionId }, 'Session initialized');
    }

    // Count compaction boundary events
    if (msg.type === 'system' && msg.subtype === 'compact_boundary') {
      compactionCount++;
      logger.session.warn({ compactionCount, sessionId }, 'Compaction boundary detected');
    }

    // Track tool calls for stuck detection
    if (stuckDetector && msg.type === 'assistant') {
      const content = msg.content as Array<Record<string, unknown>> | undefined;
      if (content) {
        for (const block of content) {
          if (block.type === 'tool_use') {
            const toolName = block.name as string;
            const toolInput = JSON.stringify(block.input ?? {});
            if (stuckDetector.record(toolName, toolInput)) {
              logger.stuck.error({ toolName, sessionId }, 'Stuck agent detected');
              controller.abort();
              return {
                success: false,
                sessionId,
                compactionCount,
                thresholdHit: false,
                costUsd: 0,
                resultSubtype: 'stuck',
                stuck: true,
              };
            }
          }
        }
      }
    }

    // Capture result message
    if (msg.type === 'result') {
      resultMessage = msg;
    }
  }

  if (!resultMessage) {
    throw new Error('Stream ended without SDKResultMessage — no result received');
  }

  const subtype = resultMessage.subtype as string;
  const costUsd = (resultMessage.total_cost_usd as number) ?? 0;
  const thresholdHit = compactionCount >= config.compactionThreshold;

  logger.session.info(
    { sessionId, subtype, costUsd, compactionCount, thresholdHit },
    'Session complete',
  );

  return {
    success: subtype === 'success',
    sessionId,
    compactionCount,
    thresholdHit,
    costUsd,
    resultSubtype: subtype,
    stuck: false,
  };
}
