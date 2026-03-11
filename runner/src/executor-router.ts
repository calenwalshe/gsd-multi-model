import { spawn, spawnSync } from 'node:child_process';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { join, basename } from 'node:path';
import type { CodexTaskResult, Notifier, RunnerConfig } from './types.js';
import type { SessionResult } from './session-runner.js';
import type { StuckDetector } from './stuck-detector.js';

export interface PlanTask {
  taskNum: number;
  executor: 'codex' | 'claude';
  name: string;
  actionBlock: string;   // raw <action>...</action> text for Claude retry prompt
  doneBlock: string;     // raw <done>...</done> text for Claude retry prompt
}

/**
 * Parse task blocks from PLAN.md content.
 * Extracts taskNum (1-based), executor attribute, name, action block, and done block.
 * Tasks without executor attribute default to 'claude'.
 */
export function parsePlanTasks(planContent: string): PlanTask[] {
  const tasks: PlanTask[] = [];

  // Match all <task ...>...</task> blocks
  const taskBlockRegex = /<task\s([^>]*)>([\s\S]*?)<\/task>/g;
  let match;
  let taskNum = 1;

  while ((match = taskBlockRegex.exec(planContent)) !== null) {
    const attributes = match[1];
    const taskBody = match[2];

    // Extract executor attribute
    const executorMatch = attributes.match(/executor="([^"]*)"/);
    const executor = executorMatch ? (executorMatch[1] as 'codex' | 'claude') : 'claude';

    // Extract name from <name>...</name>
    const nameMatch = taskBody.match(/<name>(.*?)<\/name>/s);
    const name = nameMatch ? nameMatch[1].trim() : '';

    // Extract action block
    const actionMatch = taskBody.match(/<action>([\s\S]*?)<\/action>/);
    const actionBlock = actionMatch ? actionMatch[1].trim() : '';

    // Extract done block
    const doneMatch = taskBody.match(/<done>([\s\S]*?)<\/done>/);
    const doneBlock = doneMatch ? doneMatch[1].trim() : '';

    tasks.push({
      taskNum,
      executor,
      name,
      actionBlock,
      doneBlock,
    });

    taskNum++;
  }

  return tasks;
}

/**
 * Check if Codex CLI is available.
 * Respects CODEX_ENABLED env var: if "false", returns false regardless of CLI.
 * Otherwise checks if 'codex' command exists in PATH.
 */
export function checkCodexAvailable(): boolean {
  // Check env var first
  if (process.env.CODEX_ENABLED === 'false') {
    return false;
  }

  // Check if codex CLI exists
  const result = spawnSync('which', ['codex'], { encoding: 'utf-8' });
  return result.status === 0;
}

/**
 * Run a single Codex task by spawning bin/codex-task.sh.
 * Parses the last non-empty JSON line from stdout.
 * Rejects with descriptive Error on parse failure.
 */
export function runCodexTask(
  planPath: string,
  taskNum: number,
  config: RunnerConfig,
): Promise<CodexTaskResult> {
  return new Promise((resolve, reject) => {
    const timeoutSeconds = config.codex?.timeoutSeconds ?? 300;
    const scriptPath = join(config.projectDir, 'bin', 'codex-task.sh');

    if (!existsSync(scriptPath)) {
      reject(new Error(`codex-task.sh not found at: ${scriptPath}`));
      return;
    }

    const args = [
      scriptPath,
      '--plan', planPath,
      '--task', String(taskNum),
      '--timeout', String(timeoutSeconds),
    ];

    const child = spawn('bash', args, {
      cwd: config.projectDir,
      stdio: ['ignore', 'pipe', 'inherit'],
    });

    let stdout = '';

    child.stdout?.on('data', (data) => {
      stdout += data.toString();
    });

    child.on('close', (code) => {
      // Parse last non-empty line as JSON
      const lines = stdout.split('\n').filter(line => line.trim());
      if (lines.length === 0) {
        reject(new Error(`No output from codex-task.sh for task ${taskNum}`));
        return;
      }

      const lastLine = lines[lines.length - 1];
      try {
        const result = JSON.parse(lastLine) as CodexTaskResult;
        resolve(result);
      } catch (err) {
        reject(new Error(`Failed to parse JSON from codex-task.sh output: ${lastLine}`));
      }
    });

    child.on('error', (err) => {
      reject(new Error(`Failed to spawn codex-task.sh: ${err.message}`));
    });
  });
}

/**
 * Run a batch of Codex tasks in parallel using Promise.allSettled.
 * For each failed task, sends an alert via notifier and marks retried=true.
 * Returns a Map of taskNum -> CodexTaskResult.
 */
export async function runCodexBatch(
  codexTasks: PlanTask[],
  planPath: string,
  config: RunnerConfig,
  notifier?: Notifier,
): Promise<Map<number, CodexTaskResult>> {
  const results = new Map<number, CodexTaskResult>();

  // Create promise for each task, carrying the task metadata
  const promises = codexTasks.map(task =>
    runCodexTask(planPath, task.taskNum, config)
      .then(result => ({ task, result, success: true }))
      .catch(err => ({ task, error: err, success: false }))
  );

  const settled = await Promise.allSettled(promises);

  for (const outcome of settled) {
    if (outcome.status === 'fulfilled') {
      const { task, result, success } = outcome.value;

      if (success && result) {
        // Task succeeded
        results.set(task.taskNum, result);
      } else {
        // Task promise resolved but indicated failure
        const error = (outcome.value as any).error;
        await notifier?.sendAlert(
          `Codex failed task ${task.taskNum} (${task.name}), retrying with Claude. Error: ${error?.message || 'unknown'}`
        );

        // Create a failed result with retried flag
        results.set(task.taskNum, {
          exit_code: 1,
          exit_reason: error?.message || 'unknown',
          task_id: `task-${task.taskNum}`,
          task_name: task.name,
          duration_seconds: 0,
          changed_files: [],
          commit_hash: '',
          merge_commit: '',
          retried: true,
        });
      }
    } else {
      // Promise rejected - should not happen since we catch, but handle anyway
      const error = outcome.reason;
      // Find which task this was for - use index
      const index = settled.indexOf(outcome);
      const task = codexTasks[index];

      await notifier?.sendAlert(
        `Codex failed task ${task.taskNum} (${task.name}), retrying with Claude. Error: ${error?.message || 'unknown'}`
      );

      results.set(task.taskNum, {
        exit_code: 1,
        exit_reason: error?.message || 'unknown',
        task_id: `task-${task.taskNum}`,
        task_name: task.name,
        duration_seconds: 0,
        changed_files: [],
        commit_hash: '',
        merge_commit: '',
        retried: true,
      });
    }
  }

  return results;
}

/**
 * Main execution router: reads PLAN.md for the given phase, parses tasks,
 * runs Codex batch first (if enabled), then Claude retries for failures,
 * then remaining Claude-executor tasks.
 *
 * If any Claude retry fails, sends alert and throws to halt execution.
 */
export async function runExecuteWithRouting(
  phase: number,
  config: RunnerConfig,
  execCommand: (prompt: string, config: RunnerConfig, controller: AbortController, stuckDetector?: StuckDetector) => Promise<SessionResult>,
  notifier?: Notifier,
): Promise<void> {
  // Find PLAN.md for this phase
  const phasesDir = join(config.projectDir, '.planning', 'phases');
  const phasePrefix = String(phase).padStart(2, '0');

  // Find phase directory
  const phaseDirs = readdirSync(phasesDir).filter(d => d.startsWith(`${phasePrefix}-`));
  if (phaseDirs.length === 0) {
    throw new Error(`No phase directory found for phase ${phase} in ${phasesDir}`);
  }

  const phaseDir = join(phasesDir, phaseDirs[0]);

  // Find PLAN.md files in phase directory
  const planFiles = readdirSync(phaseDir)
    .filter(f => f.match(new RegExp(`^${phasePrefix}-\\d+-PLAN\\.md$`)))
    .map(f => join(phaseDir, f));

  if (planFiles.length === 0) {
    throw new Error(`No PLAN.md found for phase ${phase} in ${phaseDir}`);
  }

  // Use first match (should only be one per phase/plan combo, unless executing specific plan)
  const planPath = planFiles[0];
  const planContent = readFileSync(planPath, 'utf-8');

  // Parse all tasks
  const allTasks = parsePlanTasks(planContent);

  // Separate Codex and Claude tasks
  const codexTasks = allTasks.filter(t => t.executor === 'codex');
  const claudeTasks = allTasks.filter(t => t.executor === 'claude');

  // Step 1: Run Codex batch (if enabled and tasks exist)
  const codexResults = new Map<number, CodexTaskResult>();
  const failedCodexTasks: PlanTask[] = [];

  if (config.codexEnabled && codexTasks.length > 0 && checkCodexAvailable()) {
    const batchResults = await runCodexBatch(codexTasks, planPath, config, notifier);

    for (const [taskNum, result] of batchResults.entries()) {
      codexResults.set(taskNum, result);

      // Track failed tasks for Claude retry
      if (result.exit_code !== 0 || result.retried) {
        const task = codexTasks.find(t => t.taskNum === taskNum);
        if (task) {
          failedCodexTasks.push(task);
        }
      }
    }
  }

  // Step 2: Claude retries for failed Codex tasks
  for (const task of failedCodexTasks) {
    const prompt = buildTaskRetryPrompt(task);
    const controller = new AbortController();

    const result = await execCommand(prompt, config, controller);

    if (!result.success) {
      // Double failure: Codex + Claude both failed
      await notifier?.sendAlert(
        `Phase halted: Task ${task.taskNum} (${task.name}) failed in both Codex and Claude. Execution stopped.`
      );
      throw new Error(`Phase halted: Claude retry failed for task ${task.taskNum} after Codex failure`);
    }
  }

  // Step 3: Run remaining Claude-executor tasks sequentially
  for (const task of claudeTasks) {
    const prompt = buildTaskExecutePrompt(task);
    const controller = new AbortController();

    const result = await execCommand(prompt, config, controller);

    if (!result.success) {
      await notifier?.sendAlert(
        `Phase halted: Claude task ${task.taskNum} (${task.name}) failed. Execution stopped.`
      );
      throw new Error(`Phase halted: Claude task ${task.taskNum} failed`);
    }
  }
}

/**
 * Build task-specific prompt for Claude retry after Codex failure.
 */
function buildTaskRetryPrompt(task: PlanTask): string {
  return `Retry after Codex failure. Execute ONLY this task:

${task.actionBlock}

Acceptance: ${task.doneBlock}`;
}

/**
 * Build task-specific prompt for Claude-executor tasks.
 */
function buildTaskExecutePrompt(task: PlanTask): string {
  return `Execute this task:

${task.actionBlock}

Acceptance: ${task.doneBlock}`;
}
