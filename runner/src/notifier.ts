import type { Notifier, RunnerConfig } from './types.js';
import { TelegramNotifier } from './telegram.js';
import { GChatNotifier } from './gchat.js';

interface Logger {
  telegram?: unknown;
  gchat?: unknown;
}

/**
 * Factory: reads RunnerConfig and returns the appropriate Notifier.
 * Telegram takes priority over GChat when both are configured.
 * Returns undefined if neither is configured.
 */
export function createNotifier(
  config: RunnerConfig,
  log: Logger,
): Notifier | undefined {
  if (config.telegram) {
    return new TelegramNotifier(config.telegram, log.telegram as Parameters<typeof TelegramNotifier>[1]);
  }
  if (config.gchat) {
    return new GChatNotifier(config.gchat, log.gchat as Parameters<typeof GChatNotifier>[1]);
  }
  return undefined;
}
