import { readFileSync } from 'node:fs';
import { GChatConfig, RunnerConfig, TelegramConfig, CodexConfig } from './types.js';

/**
 * Load runner configuration from environment variables.
 * Throws if PROJECT_DIR is not set.
 */
export function loadConfig(): RunnerConfig {
  const projectDir = process.env.PROJECT_DIR;
  if (!projectDir) {
    throw new Error('PROJECT_DIR environment variable is required');
  }

  // Load project brief from env var or file
  let projectBrief: string | undefined = process.env.PROJECT_BRIEF;
  if (!projectBrief && process.env.PROJECT_BRIEF_FILE) {
    try {
      projectBrief = readFileSync(process.env.PROJECT_BRIEF_FILE, 'utf-8').trim();
    } catch {
      throw new Error(`Could not read PROJECT_BRIEF_FILE: ${process.env.PROJECT_BRIEF_FILE}`);
    }
  }

  // Build TelegramConfig only if bot token is present
  let telegram: TelegramConfig | undefined;
  const botToken = process.env.GSD_TELEGRAM_BOT_TOKEN;
  if (botToken) {
    const chatId = process.env.GSD_TELEGRAM_CHAT_ID;
    if (!chatId) {
      throw new Error('GSD_TELEGRAM_CHAT_ID is required when GSD_TELEGRAM_BOT_TOKEN is set');
    }
    telegram = {
      botToken,
      chatId: parseInt(chatId, 10),
      gateTimeoutMs: parseInt(process.env.GATE_TIMEOUT_MS ?? '14400000', 10),
      heartbeatIntervalMs: parseInt(process.env.HEARTBEAT_INTERVAL_MS ?? '1800000', 10),
    };
  }

  // Build GChatConfig only if space ID is present (and Telegram not configured)
  let gchat: GChatConfig | undefined;
  const gchatSpaceId = process.env.GSD_GCHAT_SPACE_ID;
  if (gchatSpaceId && !telegram) {
    gchat = {
      spaceId: gchatSpaceId,
      gateTimeoutMs: parseInt(process.env.GATE_TIMEOUT_MS ?? '14400000', 10),
      heartbeatIntervalMs: parseInt(process.env.HEARTBEAT_INTERVAL_MS ?? '1800000', 10),
      pollIntervalMs: parseInt(process.env.GCHAT_POLL_INTERVAL_MS ?? '30000', 10),
    };
  }

  return {
    projectDir,
    projectBrief,
    maxTurns: parseInt(process.env.MAX_TURNS ?? '75', 10),
    maxBudgetUsd: parseFloat(process.env.MAX_BUDGET_USD ?? '5.0'),
    compactionThreshold: parseInt(process.env.COMPACTION_THRESHOLD ?? '2', 10),
    logLevel: process.env.LOG_LEVEL ?? 'info',
    stuckDetector: {
      windowSize: parseInt(process.env.STUCK_WINDOW_SIZE ?? '20', 10),
      threshold: parseInt(process.env.STUCK_THRESHOLD ?? '5', 10),
      readOnlyMultiplier: parseInt(process.env.STUCK_READONLY_MULTIPLIER ?? '2', 10),
    },
    telegram,
    gchat,
    codexEnabled: process.env.CODEX_ENABLED !== 'false',
    codex: {
      timeoutSeconds: parseInt(process.env.CODEX_TIMEOUT_SECONDS ?? '300', 10),
    },
  };
}
