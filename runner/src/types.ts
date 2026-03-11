export type GsdAction =
  | { type: 'init-project'; brief: string }
  | { type: 'plan'; phase: number }
  | { type: 'execute'; phase: number }
  | { type: 'verify'; phase: number }
  | { type: 'resume' }
  | { type: 'done' }
  | { type: 'error'; reason: string };

export interface ParsedState {
  currentPhase: number;
  totalPhases: number;
  plansInPhase: number;
  plansComplete: number;
  status: string;
}

export interface PhaseInfo {
  number: number;
  name: string;
  complete: boolean;
}

export interface Notifier {
  requestGateApproval(message: string): Promise<boolean>;
  sendProgress(text: string): Promise<void>;
  sendAlert(text: string): Promise<void>;
  startHeartbeat(): void;
  stop(): Promise<void>;
}

export interface TelegramConfig {
  botToken: string;
  chatId: number;
  gateTimeoutMs: number;      // default 4 hours
  heartbeatIntervalMs: number; // default 30 minutes
}

export interface GChatConfig {
  spaceId: string;
  // auth: TODO — figure out service account vs OAuth when deploying at Meta
  gateTimeoutMs: number;      // default 4 hours
  heartbeatIntervalMs: number; // default 30 minutes
  pollIntervalMs: number;      // default 30 seconds
}

export interface CodexConfig {
  timeoutSeconds: number;  // default 300; from CODEX_TIMEOUT_SECONDS env or config.json codex.timeout_seconds
}

export interface CodexTaskResult {
  exit_code: number;
  exit_reason: string;
  task_id: string;
  task_name: string;
  duration_seconds: number;
  changed_files: string[];
  commit_hash: string;
  merge_commit: string;
  retried?: boolean;
}

export interface StuckDetectorConfig {
  windowSize: number;
  threshold: number;
  readOnlyMultiplier: number;
}

export interface RunnerConfig {
  projectDir: string;
  projectBrief?: string;
  maxTurns: number;
  maxBudgetUsd: number;
  compactionThreshold: number;
  logLevel: string;
  stuckDetector: StuckDetectorConfig;
  telegram?: TelegramConfig;
  gchat?: GChatConfig;
  codexEnabled: boolean;
  codex?: CodexConfig;
}
