import { readFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';

/**
 * GSD command definitions: maps action types to their command files
 * and the workflow/reference files they depend on.
 */
const GSD_COMMANDS_DIR = join(process.env.HOME ?? '', '.claude/commands/gsd');
const GSD_HOME = join(process.env.HOME ?? '', '.claude/get-shit-done');

interface CommandMeta {
  commandFile: string;
  body: string;
  atRefs: string[];
}

/**
 * Parse a GSD command .md file.
 * Strips YAML frontmatter and extracts @/path references.
 */
function parseCommandFile(filePath: string): CommandMeta {
  const raw = readFileSync(filePath, 'utf-8');

  // Strip YAML frontmatter
  let body = raw;
  if (raw.startsWith('---')) {
    const endIdx = raw.indexOf('---', 3);
    if (endIdx !== -1) {
      body = raw.slice(endIdx + 3).trim();
    }
  }

  // Extract @/path/to/file references
  const atRefs: string[] = [];
  const refPattern = /@(\/[^\s)]+)/g;
  let match;
  while ((match = refPattern.exec(body)) !== null) {
    atRefs.push(match[1]);
  }

  return { commandFile: filePath, body, atRefs };
}

/**
 * Read a file and return its contents, or a placeholder if missing.
 */
function readRef(filePath: string): string {
  try {
    return readFileSync(filePath, 'utf-8');
  } catch {
    return `[File not found: ${filePath}]`;
  }
}

/**
 * Expand a GSD command into a full prompt by resolving all @ references.
 * Inlines referenced file contents after the command body.
 */
function expandCommand(meta: CommandMeta): string {
  let prompt = meta.body;

  // Append referenced files as context sections
  if (meta.atRefs.length > 0) {
    prompt += '\n\n---\n\n# Referenced Context Files\n\n';
    for (const ref of meta.atRefs) {
      const content = readRef(ref);
      prompt += `## ${ref}\n\n${content}\n\n`;
    }
  }

  return prompt;
}

/**
 * Map GSD action types to their command file names.
 */
const ACTION_COMMAND_MAP: Record<string, string> = {
  'init-project': 'new-project.md',
  'research': 'research-project.md',
  'define-requirements': 'define-requirements.md',
  'create-roadmap': 'create-roadmap.md',
  'plan': 'plan-phase.md',
  'execute': 'execute-phase.md',
  'verify': 'verify-work.md',
  'resume': 'resume-work.md',
};

export interface ExpandedPrompt {
  prompt: string;
  commandFile: string;
}

/**
 * Build a fully expanded prompt for a GSD action.
 *
 * @param actionType - The GSD action type (e.g., 'init-project', 'plan')
 * @param args - Optional arguments (e.g., phase number, project brief)
 * @returns The expanded prompt ready for query()
 */
export function expandActionPrompt(
  actionType: string,
  args?: { brief?: string; phase?: number },
): ExpandedPrompt {
  const commandFileName = ACTION_COMMAND_MAP[actionType];
  if (!commandFileName) {
    throw new Error(`No command mapping for action type: ${actionType}`);
  }

  const commandPath = join(GSD_COMMANDS_DIR, commandFileName);
  if (!existsSync(commandPath)) {
    throw new Error(`Command file not found: ${commandPath}`);
  }

  const meta = parseCommandFile(commandPath);
  let prompt = expandCommand(meta);

  // Prepend brief for init-project
  if (actionType === 'init-project' && args?.brief) {
    prompt = `IMPORTANT: This is a fully autonomous session with NO user interaction available. Do NOT use AskUserQuestion — there is no user to respond. Use all recommended defaults for every config option (Coarse granularity, Parallel execution, Yes to git tracking, Yes to research, Yes to plan check, Yes to verifier, Balanced AI models, YOLO mode). Create .planning/config.json with these defaults directly without asking.

Here is the project brief — use this as the project description:\n\n${args.brief}\n\nUse --auto mode.\n\n${prompt}`;
  }

  // Add autonomous instruction for all action types
  if (actionType !== 'init-project') {
    prompt = `IMPORTANT: This is a fully autonomous session with NO user interaction available. Do NOT use AskUserQuestion — there is no user to respond. Use recommended defaults for any decisions.\n\n${prompt}`;
  }

  // Replace $ARGUMENTS with phase number where applicable
  if (args?.phase !== undefined) {
    prompt = prompt.replace(/\$ARGUMENTS/g, String(args.phase));
  }

  return { prompt, commandFile: commandPath };
}
