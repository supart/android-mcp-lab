# Android MCP Lab Public Stable Handoff

Updated: 2026-10-19

## Current Stable Line

- Source version: `0.1.3`
- Public branch: `public/stable-0.1.3`
- Stable MCP entry: `android_lab`
- Stable tool catalog: 63 tools (57 pinned upstream tools and 6 Global Lab management tools)
- Canonical Skill: `skill/ty-android-mcp`, version `0.2.0`
- Pinned companion: `android-remote-control-mcp` `v1.11.1`
- Existing stable installation/runtime baseline: `SOURCE_AND_INSTALL_VERIFIED`
- Public HEAD install parity: pending. The public canonical Skill has newer
  workspace-neutral rules than the global Skill and `install/0.1.3`; the
  installation copy also does not yet contain `VERSION` or `CHANGELOG.md`.
- Public-prep batch: completed locally on 2026-10-19. GitHub publication uses
  a clean root snapshot so historical machine-local paths are not exposed;
  the full internal history remains local.
- Public-prep evidence: `verification/public-repo-20261019.json`.

The stable line contains the Windows/Codex Broker, stdio proxy, Supervisor, registry, lease/session recovery, Bootstrap, canonical Skill, tests, and public documentation. It does not include real-time emulator video.

## Verified Stable Behavior

Existing sanitized evidence records show:

- TypeScript typecheck/build, PowerShell parsing, vNext/status contracts, configuration acceptance, JSON parsing, and sensitive-data scans passed for the stable line;
- Codex loaded the stable 0.1.3 installation and exposed 63 tools after restart;
- the no-credentials `codex_api36` smoke reached `startupPhase=ready`, `bootCompleted=true`, `adbRegistered=true`, and `companionReady=true`;
- Companion open plus fresh screen read passed;
- lease acquire/release completed without a retained lease;
- Provider request count was 0 and credential read was false.

This public-repository cleanup is not a new Android runtime acceptance run. It must not be described as a new `RUNTIME_PASS`.

## Canonical Skill v0.2.0

The public Skill provides bounded self-healing behavior:

- `android_lab_status` is authoritative for runtime readiness;
- registry/runtime disagreement blocks side effects until a fresh status resolves it;
- Broker Stop -> Ensure -> health recovery is allowed once;
- persistent proxy `fetch failed` requires a Codex restart;
- `companion_not_ready` opens the registered companion through MCP before Broker recovery;
- project APK mapping is task-local via `TY_ANDROID_MCP_APK`, `TY_ANDROID_MCP_INSTALL_SCRIPT`, and `TY_ANDROID_MCP_PACKAGE`;
- every UI write, install, launch, intent, or navigation transition requires a fresh screen read;
- lease release is finally-style and has one bounded health-checked retry.

The Skill contains no user-specific workspace path or project-specific package mapping.

## Preview Boundary

`feature/mirror-realtime-0.1.3-preview.1` is a separate 66-tool experiment. It remains `PROTOCOL_MOCK_ONLY`.

A gRPC screenshot frame is not evidence of real-time Browser video. Until real WebRTC first-frame, continuous playback, disconnect, TTL, page-close, lease-revoke, and Broker-exit cleanup pass, `mirror.start` must not be presented as a stable endpoint. The stable branch contains no Mirror tools and never falls back to scrcpy, VNC, MJPEG, WebSocket frame streaming, independent ADB, or LAN control.

## Public Repository Boundary

Track:

- `bridge/`, `registry/`, `scripts/`, `skill/`, `tests/`, `docs/`, public metadata, and sanitized verification records;
- source manifests and SHA-256 sidecars.

Do not track:

- ZIP/APK/bundled Node payloads;
- `node_modules`, runtime staging, AVD snapshots;
- Broker state, leases, sessions, logs, configuration backups;
- credentials, DPAPI, Authorization/OAuth values, tokens, raw UI trees, image bytes, screenshots, or private session content.

No GitHub publishing remote is configured by this batch and no push is performed.

## Still Pending

- full session/Broker/lease lifecycle matrix;
- second-Windows installation and smoke;
- companion-native `type_clear_text` and `dismiss_keyboard` fixes;
- real Codex Browser WebRTC Mirror first frame and lifecycle acceptance;
- release-flow synchronization of the public canonical Skill to the global
  Skill and `install/0.1.3`, followed by a Codex restart and parity check.

## Exact Next Breakpoint

The stable public-tree validation suite is complete: a fresh isolated copy passed `npm ci` (145 packages), typecheck, build, bundle dry-run, vNext/status contracts, and `dist` 8/8 SHA-256 parity. PowerShell AST, JavaScript syntax, JSON parsing, official Skill validation, tracked-file sensitive/path scans, artifact hash checks, and `git diff --check` also passed. The source repository is clean. Public-HEAD Skill installation parity is a separate release step and remains pending; the next action is GitHub publication from the clean public root snapshot. Do not start or stop an AVD, acquire a lease, change the companion APK, or merge Mirror preview as part of this breakpoint.
