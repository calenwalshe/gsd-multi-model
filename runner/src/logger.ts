import pino from 'pino';

const COMPONENTS = ['session', 'telegram', 'loop', 'gate', 'stuck'] as const;
type Component = (typeof COMPONENTS)[number];

export type Logger = Record<Component, pino.Logger>;

/**
 * Create a logger instance with child loggers for each component.
 * @param level - pino log level (default: 'info')
 */
export function createLogger(level?: string): Logger {
  const root = pino({ name: 'gsd-runner', level: level ?? 'info' });

  const result = {} as Record<Component, pino.Logger>;
  for (const c of COMPONENTS) {
    result[c] = root.child({ component: c });
  }
  return result;
}

/** Default logger instance using LOG_LEVEL env var */
export const logger = createLogger(process.env.LOG_LEVEL);
