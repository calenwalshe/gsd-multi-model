# Save Entry: gsd-runner Monorepo Merge + GChat Notifier

**Date**: 2026-03-09
**Type**: session
**Tags**: gsd-multi-model, gsd-runner, runner, notifier, gchat, telegram, typescript

## Context
- **What**: Merged gsd-runner into gsd-multi-model as `runner/` subdirectory, added Notifier abstraction (Telegram + GChat)
- **Why**: Consolidate skills layer + runner layer into one repo
- **Where**: `/home/calenwalshe/gdrive/repos/gsd-multi-model/`

## What Was Done (Phase 9 — COMPLETE)

### Files Created
- `runner/src/gchat.ts` — GChatNotifier implements Notifier (REST API + polling, auth TODO)
- `runner/src/notifier.ts` — factory `createNotifier()` (Telegram > GChat > undefined)

### Files Modified
- `runner/src/types.ts` — added `Notifier` interface, `GChatConfig`, `gchat?` on RunnerConfig
- `runner/src/telegram.ts` — renamed `TelegramBot` → `TelegramNotifier`, added `implements Notifier`
- `runner/src/config.ts` — added GChat env var loading (GSD_GCHAT_SPACE_ID, GCHAT_POLL_INTERVAL_MS)
- `runner/src/index.ts` — uses `Notifier` interface + `createNotifier()` factory throughout
- `runner/.env.example` — added Telegram + GChat sections with shared timing vars
- `install.sh` — added step 7: runner npm install + summary section
- `.planning/ROADMAP.md` — added v1.3 milestone (Phase 9 complete, Phase 10 deferred)

### Moved from gsd-runner
All source files copied via mclone (gdrive FUSE mount was unstable during session):
`src/`, `package.json`, `tsconfig.json`, `vitest.config.ts`, `GSD-STYLE.md`

## Verification Status
- ✅ `npm run build` — compiles cleanly (23.76 KB ESM)
- ✅ `tsc --noEmit` — zero type errors
- ❌ `npm test` — pre-existing env issue: Node v16 on OD, vitest requires v18+
- ✅ All files confirmed on Google Drive via mclone

## Key Technical Decisions
1. **Telegram > GChat priority** — if both env vars set, Telegram wins (home context)
2. **GChat auth is a TODO stub** — throws clear error pointing to docs; Phase 10 tracks this
3. **GChatNotifier polls** — no webhooks; polls every `GCHAT_POLL_INTERVAL_MS` (default 30s)
4. **notifier.ts reuses `log.telegram`** for GChat — logger has no `gchat` child component
5. **TelegramNotifier.start()** — called from main() via instanceof check (needed for polling setup)

## Env Vars Added
```
GSD_GCHAT_SPACE_ID=spaces/AAAAxxxxxx
GSD_GCHAT_AUTH_TOKEN=...   (TBD)
GCHAT_POLL_INTERVAL_MS=30000
GATE_TIMEOUT_MS=14400000
HEARTBEAT_INTERVAL_MS=1800000
```

## Architecture Diagram (key insight)
```
Daemon (dumb coordinator)     Claude Agent SDK (all AI)
─────────────────────────     ─────────────────────────
reads .planning/ markdown  →  builds prompt → runs session
state machine decides      →  Claude reads/writes/tests code
notifier sends gate        →  human approves → loop continues
```

## Next Steps (Phase 10 — PENDING)
- Implement GChat auth via ADC or service account (no manual token)
- Integration test against a real Meta GChat space
- Consider adding `gchat` as a named logger component in logger.ts

## gdrive Mount Note
During this session the gdrive FUSE mount was unstable (npm install caused heavy I/O).
**Workaround**: use `mclone cat` / `mclone ls` to verify files directly:
```bash
http_proxy="http://fwdproxy:8080" https_proxy="http://fwdproxy:8080" \
  mclone ls gdrive:claude/repos/gsd-multi-model/runner/src/
```

## Restore Command
```
cd /home/calenwalshe/gdrive/repos/gsd-multi-model
# Then resume from this save file context
```
