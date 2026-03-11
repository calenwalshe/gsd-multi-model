#!/usr/bin/env node
"use strict";

// ============================================================
// gsd-tools-gate.cjs -- Gate CLI wrapper
//
// Standalone Node.js CLI for gate operations. Invoked directly
// (not as a module) to avoid modifying the GSD base gsd-tools.cjs.
//
// Usage:
//   node bin/gsd-tools-gate.cjs run [--plan-path <path>] [--raw]
//   node bin/gsd-tools-gate.cjs check-architecture [--files <file1> <file2>...]
//   node bin/gsd-tools-gate.cjs status
//
// Output:
//   run:                JSON gate result (+ human stderr from gate-check.sh)
//   check-architecture: JSON architecture result
//   status:             Gate configuration summary
// ============================================================

const { execSync } = require("child_process");
const path = require("path");
const fs = require("fs");

const SCRIPT_DIR = __dirname;
const PROJECT_ROOT = path.resolve(SCRIPT_DIR, "..");

const args = process.argv.slice(2);
const command = args[0] || "help";

// --- Helpers ---

function findFlag(flag) {
  const idx = args.indexOf(flag);
  return idx !== -1;
}

function findFlagValue(flag) {
  const idx = args.indexOf(flag);
  if (idx !== -1 && idx + 1 < args.length) {
    return args[idx + 1];
  }
  return null;
}

function collectFlagValues(flag) {
  const idx = args.indexOf(flag);
  if (idx === -1) return [];
  const values = [];
  for (let i = idx + 1; i < args.length; i++) {
    if (args[i].startsWith("--")) break;
    values.push(args[i]);
  }
  return values;
}

function loadConfig() {
  const configPath = path.join(PROJECT_ROOT, ".planning", "config.json");
  try {
    return JSON.parse(fs.readFileSync(configPath, "utf8"));
  } catch {
    return {};
  }
}

// ============================================================
// Commands
// ============================================================

function runGates() {
  const planPath = findFlagValue("--plan-path");
  const raw = findFlag("--raw");

  const gateScript = path.join(SCRIPT_DIR, "gate-check.sh");
  if (!fs.existsSync(gateScript)) {
    const err = { passed: false, error: "gate-check.sh not found at " + gateScript };
    process.stdout.write(JSON.stringify(err, null, raw ? 0 : 2) + "\n");
    process.exit(1);
  }

  let cmd = "bash " + JSON.stringify(gateScript);
  if (planPath) {
    cmd += " --plan-path " + JSON.stringify(planPath);
  }

  try {
    // Run gate-check.sh: stdout = JSON, stderr = human-readable (passed through)
    const result = execSync(cmd, {
      cwd: PROJECT_ROOT,
      stdio: ["pipe", "pipe", "inherit"],
      timeout: 30000,
    });
    const output = result.toString("utf8").trim();
    if (raw) {
      process.stdout.write(output + "\n");
    } else {
      // Pretty-print the JSON
      try {
        const parsed = JSON.parse(output);
        process.stdout.write(JSON.stringify(parsed, null, 2) + "\n");
      } catch {
        process.stdout.write(output + "\n");
      }
    }
    process.exit(0);
  } catch (err) {
    // Gate failed (exit code 1) -- still has JSON on stdout
    if (err.stdout) {
      const output = err.stdout.toString("utf8").trim();
      if (raw) {
        process.stdout.write(output + "\n");
      } else {
        try {
          const parsed = JSON.parse(output);
          process.stdout.write(JSON.stringify(parsed, null, 2) + "\n");
        } catch {
          process.stdout.write(output + "\n");
        }
      }
    }
    process.exit(1);
  }
}

function checkArchitecture() {
  const files = collectFlagValues("--files");
  const validator = path.join(SCRIPT_DIR, "validate-architecture.sh");

  if (!fs.existsSync(validator)) {
    const err = { passed: false, error: "validate-architecture.sh not found at " + validator };
    process.stdout.write(JSON.stringify(err, null, 2) + "\n");
    process.exit(1);
  }

  const archConfig = ".architecture.json";
  let cmd = "bash " + JSON.stringify(validator) + " " + JSON.stringify(archConfig);
  if (files.length > 0) {
    cmd += " " + files.map(f => JSON.stringify(f)).join(" ");
  }

  try {
    const result = execSync(cmd, {
      cwd: PROJECT_ROOT,
      stdio: ["pipe", "pipe", "pipe"],
      timeout: 15000,
    });
    process.stdout.write(result.toString("utf8"));
    process.exit(0);
  } catch (err) {
    if (err.stdout) {
      process.stdout.write(err.stdout.toString("utf8"));
    }
    process.exit(1);
  }
}

function showStatus() {
  const config = loadConfig();
  const gates = config.gates || {};

  const status = {
    gates_enabled: gates.enabled !== undefined ? gates.enabled : true,
    lint: {
      enabled: gates.lint ? (gates.lint.enabled !== undefined ? gates.lint.enabled : true) : true,
      command: gates.lint ? (gates.lint.command || "(auto-detect)") : "(auto-detect)",
      auto_detect: gates.lint ? (gates.lint.auto_detect !== undefined ? gates.lint.auto_detect : true) : true,
    },
    architecture: {
      enabled: gates.architecture ? (gates.architecture.enabled !== undefined ? gates.architecture.enabled : true) : true,
      config_path: gates.architecture ? (gates.architecture.config_path || ".architecture.json") : ".architecture.json",
    },
    structural: {
      enabled: gates.structural ? (gates.structural.enabled !== undefined ? gates.structural.enabled : true) : true,
    },
    timeout_seconds: gates.timeout_seconds || 10,
    on_timeout: gates.on_timeout || "warn",
  };

  process.stdout.write(JSON.stringify(status, null, 2) + "\n");
}

function showHelp() {
  process.stderr.write(`
gsd-tools-gate -- Gate CLI wrapper

Commands:
  run [--plan-path <path>] [--raw]    Run all enabled gates on staged files
  check-architecture [--files f1 f2]  Run architecture validation only
  status                              Show gate configuration

Examples:
  node bin/gsd-tools-gate.cjs run
  node bin/gsd-tools-gate.cjs run --plan-path .planning/phases/02-deterministic-gates/02-03-PLAN.md
  node bin/gsd-tools-gate.cjs run --raw
  node bin/gsd-tools-gate.cjs check-architecture --files bin/gate-check.sh
  node bin/gsd-tools-gate.cjs status
`);
}

// ============================================================
// Dispatch
// ============================================================

switch (command) {
  case "run":
    runGates();
    break;
  case "check-architecture":
    checkArchitecture();
    break;
  case "status":
    showStatus();
    break;
  case "help":
  case "--help":
  case "-h":
    showHelp();
    break;
  default:
    process.stderr.write("Unknown command: " + command + "\n");
    showHelp();
    process.exit(1);
}
