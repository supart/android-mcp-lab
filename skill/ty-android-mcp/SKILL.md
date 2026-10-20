---
name: ty-android-mcp
description: Run self-healing, lease-bound Android Studio emulator workflows through the global Android MCP Lab for builds, APK installation, app launch, UI actions, screen state, and regression tests. Use for emulator testing, Android UI interaction, Debug APK launch, or Android smoke tests. Also invoke with $ty-android-mcp.
---

# TY Android MCP

Use the global `android_lab` MCP as the only Android control plane. This Skill is the workflow and recovery layer; it must never bypass the Broker with direct ADB clicks, input, screenshots, shell UI automation, scrcpy, VNC, or network devices.

Read these references when the task needs the corresponding detail:

- [Workflow recipes](references/workflow-recipes.md) for the complete self-healing state machine and APK flow.
- [Device policy](references/device-policy.md) before selecting a device or handling cleanup.
- [Evidence protocol](references/evidence-protocol.md) before saving a verification record.

## Non-negotiable invariants

- Discover the available `android_lab_*` tools from the current MCP catalog, including `android_lab_list_apps` when package verification is needed. Do not invent a tool or assume hot reload. If a required tool is missing, stop and report the exact capability plus the Codex restart/install recovery.
- Prefer the explicitly requested enabled no-credentials emulator; otherwise prefer `codex_api36`. Reject devices marked `contains-credentials` or `preserve`, physical devices, LAN endpoints, disabled/unknown devices, and ABI/API-blocked AVDs.
- Acquire one lease before any write, installation, launch, UI action, or test operation. Release that lease in `finally`-style cleanup on success, failure, timeout, cancellation, interruption, and process exit.
- `bootCompleted=true` is not ready. Require `adbRegistered=true` and `companionReady=true` before UI work.
- After every UI write, installation, launch, intent, navigation key, keyboard transition, or app relaunch, read a fresh screen state. Never reuse node ids across a write or state transition.
- Prefer `type_replace_text`; verify the final value for every non-sensitive field. Credential fields are always blocked: never type, copy, paste, OCR, screenshot, persist, or echo API keys, OAuth, Authorization, DPAPI, Worker Keys, tokens, or private session text.
- `dismiss_keyboard` is valid only when an IME is observed, and its disappearance must be confirmed. `BACK` is navigation only after a fresh read proves no IME is open.

## Lifecycle and source of truth

- The emulator is supervisor-managed, not a permanent resident service. A Codex, Broker, or emulator restart may leave the AVD offline, recreate the emulator process, stop the Companion, or remove the installed app package from the active instance. Never assume APK installation, app process, session data, or Companion state survived a restart.
- `android_lab_devices` is the registry and safety-policy source. `android_lab_status` is the runtime readiness source and wins whenever the two snapshots disagree. Classify disagreement as `registry_status_inconsistent`; do not perform UI, install, or launch work until a bounded fresh status read resolves it.
- A Broker health response of `ready` proves only that the local Broker is listening. It does not prove the Codex MCP proxy session or the selected emulator session is usable.

## Self-Healing Startup

Use one workflow ledger with `recoveryCount=0`, a per-operation `operationAttempts<=2`, one lease reference, and a sanitized failure category. The bounded state machine is:

```text
registry -> runtime status (authoritative)
offline/starting -> guest_boot -> adb_unavailable
                         |
                         v
                  companion_not_ready --open Companion--> ready
                         |
                         v
                       failed
```

1. Discover the current MCP catalog. If a required tool is missing, stop with the exact missing capability and the Codex restart/install recovery; do not invent a substitute tool.
2. Call `android_lab_devices` to select a registered enabled no-credentials device, then call `android_lab_status` for the same device. Treat `status` as authoritative. If registry and runtime disagree, record `registry_status_inconsistent`, discard the stale snapshot, and perform one bounded fresh status read before any side effect.
3. Acquire exactly one lease before `start`, installation, launch, UI actions, or tests. Preserve this lease id across Broker recovery; never acquire a second lease as a workaround.
4. If runtime status is `offline` or `starting`, call `android_lab_start` at most once for the current startup attempt and poll with bounded backoff. Require `bootCompleted=true`, `adbRegistered=true`, and `companionReady=true` before UI or package work.
5. If `bootCompleted=true` and `adbRegistered=true` but `companionReady=false`, classify `companion_not_ready` and first open the device-registered `mcpPackage` through MCP `android_lab_open_app`. Immediately call `android_lab_get_screen_state`, then poll status. Do not restart the Broker merely because Companion is not yet running.
6. Enter the single Broker recovery only when a read or required operation returns `fetch failed`, `session_recovery_required`, `adb_unavailable`, or Companion launch/status calls remain unavailable after the bounded Companion attempt. A `catalog_mismatch` may use this recovery only before any side effect and only to reload the configured installation; a persistent mismatch stops immediately:
   - Prefer the installation path already configured for the global `android_lab` MCP when it contains both official scripts. Only when that path is unavailable, inspect `%LOCALAPPDATA%\WhiteCodex\AndroidMcpLab\install\*` and select the newest official semantic-version installation whose `scripts` directory contains both scripts. Use: `Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'WhiteCodex\AndroidMcpLab\install') -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' -and (Test-Path (Join-Path $_.FullName 'scripts\Stop-AndroidLabBroker.ps1')) -and (Test-Path (Join-Path $_.FullName 'scripts\Ensure-AndroidLabBroker.ps1')) } | Sort-Object { [version]$_.Name } -Descending`.
   - Before Stop, use only sanitized Lab status or lease-presence evidence to detect another active workflow. If another task may hold a lease, classify `broker_recovery_deferred` and require coordination; do not restart the shared Broker.
   - Run Stop, then Ensure with stdout/stderr suppressed; retain only a sanitized exit summary.
   - Poll `http://127.0.0.1:18190/health` until JSON `status=ready` or the finite timeout expires.
   - Increment `recoveryCount` to `1`, then call `android_lab_devices` and `android_lab_status` again. Reconcile registry/runtime state before continuing. If a lease existed, keep that original lease reference; the first later side effect must use it, and an invalid/not-owned response becomes `lease_recovery_required` rather than a second acquire.
   - If health is ready but the Codex MCP proxy still returns `fetch failed`, classify `session_recovery_required`, stop side effects, and require a Codex restart.
7. Never recover the Broker more than once, never retry a side-effect operation against an invalid session, and never mask readiness errors as a generic timeout. Persistent `catalog_mismatch` is not retried.

## Project APK installation and launch

For a project-specific Debug APK, require an explicit task-local mapping. Do
not invent or persist a workspace path. A portable invocation can provide:

```text
APK:    $env:TY_ANDROID_MCP_APK
Script: $env:TY_ANDROID_MCP_INSTALL_SCRIPT
Package: $env:TY_ANDROID_MCP_PACKAGE
```

If any value is missing, classify `project_apk_not_configured` and stop
before installation. Resolve the APK and script to canonical paths and require
regular files inside the current project root (not UNC paths or reparse
points), unless the user explicitly authorized another path. Inspect the
project's existing installer and confirm that it consumes the exact APK path
or accepts that path as a literal argument. Invoke it with a literal path and
structured arguments, never a concatenated shell command. Otherwise classify
`project_installer_untrusted`; do not replace it with direct ADB commands.

1. After the emulator is `ready`, call `android_lab_list_apps` (or the exact package-list tool exposed by the current catalog) to check whether the package is installed. If no package-list MCP capability exists, stop with a missing-capability report; do not assume the package is missing and do not install blindly. Repeat this check after any emulator or Broker restart.
2. If the package is missing, record the APK SHA-256, run the reviewed install script for that exact APK, redact its output, immediately obtain a fresh screen state, then check package presence again through MCP. A restart means the package may have disappeared; always re-check instead of assuming persistence.
3. Open the package with MCP `android_lab_open_app`, immediately obtain a fresh screen state, and only then continue. If there is no launchable activity, re-check `ready` status and package presence once, then classify `no_launchable_activity`; do not loop.
4. Any subsequent tap, type, scroll, clear, Back/Home/Recents, or intent follows the fresh-read and non-sensitive field-value rules above. A successful launch does not prove the app is ready until the fresh screen state identifies the expected package/activity.

## Retry and failure boundaries

- Short Broker/network errors: at most two attempts per operation and one Broker recovery per workflow.
- `catalog_mismatch`: before side effects, it may consume the single recovery only to reload the configured installation; persistent mismatch stops and reports expected/observed metadata without relaxing the tool count or schema gate.
- `session_recovery_required`: recover once for read-only setup; do not retry a side effect automatically. Persistent proxy failure requires a Codex restart.
- `registry_status_inconsistent`: do not use the stale registry snapshot for a side effect; obtain a bounded fresh runtime status and classify the final state.
- Cancellation: release the lease, do not retry.
- 404, configuration errors, disabled/unknown devices, and `no_launchable_activity`: perform the documented finite diagnosis once, then stop.
- Lease release failure: check Broker health, safely retry release once if health is `ready`, then classify `cleanup_failed`. Do not kill processes or use direct ADB.
- Final reports must include stage, failure category, recovery actions, package-installed state, companion-opened state, fresh-read result, lease cleanup, and one precise next step. Never hide a readiness error behind `timeout`.

## Safe evidence

For each workflow, save only the sanitized fields in [evidence-protocol.md](references/evidence-protocol.md): device id, API level, screen size, startup phase, companion readiness, package/app/fresh-read state, provider request count, credential-read flag, failure category, recovery count, session, lease, and cleanup. Do not save tokens, keys, authorization data, DPAPI, Base64, image bytes, raw UI trees, complete screenshots, or private session text.

## Manual Codex restart boundaries

Tell the user to restart Codex, and stop automation, when:

- required `android_lab_*` tools are absent;
- Broker health is `ready` but the MCP proxy still returns `fetch failed` after the single recovery;
- `session_recovery_required` remains after the single recovery;
- the loaded catalog/schema differs from the installed catalog;
- an invalid session holds a lease and the required operation is a side effect;
- Global MCP or Skill installation/configuration changed (MCP and Skill loading are not hot-reloaded).

## Completion

Report the selected device, startup state, install/open/fresh-read results, tests, failure categories, recovery count, session state, and lease cleanup. Keep all output sanitized. When no expected first-screen activity, resource, or text assertion was supplied, report only package/activity plus non-error fresh-read evidence; do not claim semantic first-screen acceptance. Do not claim runtime success when a required MCP capability, companion readiness, or fresh screen state is unverified.

## Examples

- `在安卓模拟器测试这个 App`
- `启动由 TY_ANDROID_MCP_* 参数指定的 Debug 版本并读取 fresh screen state`
- `点击登录按钮，输入测试文本`
- `跑一次 Android 回归`
- `$ty-android-mcp 读取 codex_api36 当前屏幕`
