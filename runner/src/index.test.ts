import { describe, it, expect, vi, beforeEach } from 'vitest';
import { runLoop, actionToPrompt, _resetShutdownState } from './index.js';
import type { GsdAction, Notifier, RunnerConfig } from './types.js';
import type { SessionResult } from './session-runner.js';

describe('ROUTE-03: runLoop() routing branch for execute action', () => {
  beforeEach(() => {
    _resetShutdownState();
    vi.clearAllMocks();
  });

  it('should call runExecuteWithRouting when action.type=execute and codexEnabled=true', async () => {
    const mockRunExecuteWithRouting = vi.fn().mockResolvedValue(undefined);
    const mockExecCommand = vi.fn().mockResolvedValue({
      sessionId: 'test-session',
      success: true,
      costUsd: 0.5,
      thresholdHit: false,
      stuck: false,
    } as SessionResult);

    const mockNextAction = vi
      .fn()
      .mockReturnValueOnce({ type: 'execute', phase: 11 } as GsdAction)
      .mockReturnValueOnce({ type: 'done' } as GsdAction);

    const config: RunnerConfig = {
      projectDir: '/test',
      maxTurns: 10,
      maxBudgetUsd: 5,
      compactionThreshold: 2,
      logLevel: 'info',
      stuckDetector: { windowSize: 10, threshold: 0.8, readOnlyMultiplier: 1.5 },
      codexEnabled: true,
    };

    // Mock the executor-router module
    const mockCheckCodexAvailable = vi.fn().mockReturnValue(true);
    vi.doMock('./executor-router.js', () => ({
      runExecuteWithRouting: mockRunExecuteWithRouting,
      checkCodexAvailable: mockCheckCodexAvailable,
    }));

    await runLoop(config, {
      determineNextAction: mockNextAction,
      runGsdCommand: mockExecCommand,
      runCheckpoint: vi.fn().mockResolvedValue(undefined),
    });

    // When codexEnabled=true, should call runExecuteWithRouting instead of execCommand
    expect(mockRunExecuteWithRouting).toHaveBeenCalledTimes(1);
    expect(mockRunExecuteWithRouting).toHaveBeenCalledWith(
      11,
      config,
      expect.any(Function),
      undefined,
    );
    expect(mockExecCommand).not.toHaveBeenCalled();
  });

  it('should use existing Claude path when action.type=execute and codexEnabled=false', async () => {
    const mockExecCommand = vi.fn().mockResolvedValue({
      sessionId: 'test-session',
      success: true,
      costUsd: 0.5,
      thresholdHit: false,
      stuck: false,
    } as SessionResult);

    const mockNextAction = vi
      .fn()
      .mockReturnValueOnce({ type: 'execute', phase: 11 } as GsdAction)
      .mockReturnValueOnce({ type: 'done' } as GsdAction);

    const config: RunnerConfig = {
      projectDir: '/test',
      maxTurns: 10,
      maxBudgetUsd: 5,
      compactionThreshold: 2,
      logLevel: 'info',
      stuckDetector: { windowSize: 10, threshold: 0.8, readOnlyMultiplier: 1.5 },
      codexEnabled: false,
    };

    await runLoop(config, {
      determineNextAction: mockNextAction,
      runGsdCommand: mockExecCommand,
      runCheckpoint: vi.fn().mockResolvedValue(undefined),
    });

    // When codexEnabled=false, should use existing actionToPrompt + execCommand path
    expect(mockExecCommand).toHaveBeenCalledTimes(1);
    expect(mockExecCommand).toHaveBeenCalledWith(
      expect.stringContaining('execute'),
      config,
      expect.any(Object),
      undefined,
    );
  });
});

describe('ROUTE-07: verify action routing', () => {
  beforeEach(() => {
    _resetShutdownState();
    vi.clearAllMocks();
  });

  it('should always route verify action to Claude session (never Codex)', async () => {
    const mockRunExecuteWithRouting = vi.fn().mockResolvedValue(undefined);
    const mockExecCommand = vi.fn().mockResolvedValue({
      sessionId: 'test-session',
      success: true,
      costUsd: 0.5,
      thresholdHit: false,
      stuck: false,
    } as SessionResult);

    const mockNextAction = vi
      .fn()
      .mockReturnValueOnce({ type: 'verify', phase: 11 } as GsdAction)
      .mockReturnValueOnce({ type: 'done' } as GsdAction);

    const mockNotifier: Notifier = {
      requestGateApproval: vi.fn().mockResolvedValue(true),
      sendProgress: vi.fn().mockResolvedValue(undefined),
      sendAlert: vi.fn().mockResolvedValue(undefined),
      startHeartbeat: vi.fn(),
      stop: vi.fn().mockResolvedValue(undefined),
    };

    const config: RunnerConfig = {
      projectDir: '/test',
      maxTurns: 10,
      maxBudgetUsd: 5,
      compactionThreshold: 2,
      logLevel: 'info',
      stuckDetector: { windowSize: 10, threshold: 0.8, readOnlyMultiplier: 1.5 },
      codexEnabled: true, // Even with Codex enabled, verify should use Claude
    };

    await runLoop(config, {
      determineNextAction: mockNextAction,
      runGsdCommand: mockExecCommand,
      runCheckpoint: vi.fn().mockResolvedValue(undefined),
      notifier: mockNotifier,
    });

    // verify action should ALWAYS use execCommand (Claude), never runExecuteWithRouting
    expect(mockExecCommand).toHaveBeenCalledTimes(1);
    expect(mockRunExecuteWithRouting).not.toHaveBeenCalled();
    expect(mockExecCommand).toHaveBeenCalledWith(
      expect.stringContaining('verify'),
      config,
      expect.any(Object),
      undefined,
    );
  });
});

describe('actionToPrompt() for execute action', () => {
  it('should return execute prompt for execute action', () => {
    const action: GsdAction = { type: 'execute', phase: 11 };
    const prompt = actionToPrompt(action);

    expect(prompt).toBeDefined();
    expect(typeof prompt).toBe('string');
  });
});
