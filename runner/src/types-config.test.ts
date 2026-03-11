import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import type { RunnerConfig, CodexConfig, CodexTaskResult } from './types.js';
import { loadConfig } from './config.js';

describe('Task 1: Codex types and config extensions', () => {
  const originalEnv = process.env;

  beforeEach(() => {
    process.env = { ...originalEnv };
    process.env.PROJECT_DIR = '/tmp/test-project';
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  describe('CodexConfig type', () => {
    it('should define timeoutSeconds field', () => {
      const config: CodexConfig = {
        timeoutSeconds: 300,
      };
      expect(config.timeoutSeconds).toBe(300);
    });
  });

  describe('CodexTaskResult type', () => {
    it('should define all required fields', () => {
      const result: CodexTaskResult = {
        exit_code: 0,
        exit_reason: 'success',
        task_id: '11-02-1',
        task_name: 'Setup database',
        duration_seconds: 45.2,
        changed_files: ['src/db.ts', 'src/schema.ts'],
        commit_hash: 'abc123',
        merge_commit: 'def456',
      };
      expect(result.exit_code).toBe(0);
      expect(result.exit_reason).toBe('success');
      expect(result.task_id).toBe('11-02-1');
      expect(result.task_name).toBe('Setup database');
      expect(result.duration_seconds).toBe(45.2);
      expect(result.changed_files).toEqual(['src/db.ts', 'src/schema.ts']);
      expect(result.commit_hash).toBe('abc123');
      expect(result.merge_commit).toBe('def456');
    });

    it('should support optional retried field', () => {
      const result: CodexTaskResult = {
        exit_code: 1,
        exit_reason: 'error',
        task_id: '11-02-2',
        task_name: 'Build API',
        duration_seconds: 12.5,
        changed_files: [],
        commit_hash: '',
        merge_commit: '',
        retried: true,
      };
      expect(result.retried).toBe(true);
    });
  });

  describe('RunnerConfig extensions', () => {
    it('should include codexEnabled field', () => {
      const config = loadConfig();
      expect(config).toHaveProperty('codexEnabled');
      expect(typeof config.codexEnabled).toBe('boolean');
    });

    it('should include optional codex field', () => {
      const config = loadConfig();
      expect(config).toHaveProperty('codex');
      if (config.codex) {
        expect(config.codex).toHaveProperty('timeoutSeconds');
      }
    });
  });

  describe('loadConfig() Codex field population', () => {
    it('should default codexEnabled to true when CODEX_ENABLED is unset', () => {
      delete process.env.CODEX_ENABLED;
      const config = loadConfig();
      expect(config.codexEnabled).toBe(true);
    });

    it('should set codexEnabled to false when CODEX_ENABLED=false', () => {
      process.env.CODEX_ENABLED = 'false';
      const config = loadConfig();
      expect(config.codexEnabled).toBe(false);
    });

    it('should set codexEnabled to true when CODEX_ENABLED=true', () => {
      process.env.CODEX_ENABLED = 'true';
      const config = loadConfig();
      expect(config.codexEnabled).toBe(true);
    });

    it('should populate codex.timeoutSeconds from CODEX_TIMEOUT_SECONDS', () => {
      process.env.CODEX_TIMEOUT_SECONDS = '600';
      const config = loadConfig();
      expect(config.codex?.timeoutSeconds).toBe(600);
    });

    it('should default codex.timeoutSeconds to 300 when CODEX_TIMEOUT_SECONDS is unset', () => {
      delete process.env.CODEX_TIMEOUT_SECONDS;
      const config = loadConfig();
      expect(config.codex?.timeoutSeconds).toBe(300);
    });
  });
});
