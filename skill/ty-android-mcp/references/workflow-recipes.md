# Workflow Recipes

These recipes are bounded operational procedures. They describe how Codex should recover from the observed Android MCP failure chain without bypassing MCP or touching credential data.

## Self-Healing Startup

Use one workflow context with `recoveryCount=0`, a per-operation `operationAttempts<=2`, one lease reference, and a `registryStatusConsistency` field. The lease must be released in a `finally` block on every exit path. The emulator is not guaranteed to remain resident across Codex, Broker, or supervisor restarts. Any disagreement between registry and runtime UI data is recorded as `ui_state_mismatch` (or the more specific `registry_status_inconsistent`) before a fresh status read.

### 1. Broker unavailable (`fetch failed`)

1. Stop the current operation and retain only a sanitized error category.
2. Prefer the installation already configured for the global `android_lab` MCP when it contains both official scripts. Only when that path is unavailable, scan `%LOCALAPPDATA%\WhiteCodex\AndroidMcpLab\install\*` for the newest directory whose `scripts` child contains both `Stop-AndroidLabBroker.ps1` and `Ensure-AndroidLabBroker.ps1`.
3. If no matching installation exists, classify `environment_blocked` and tell the user to install Global Lab. Do not guess a version directory. A safe discovery pattern is:

   ```powershell
   Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'WhiteCodex\AndroidMcpLab\install') -Directory |
     Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' -and (Test-Path (Join-Path $_.FullName 'scripts\Stop-AndroidLabBroker.ps1')) -and (Test-Path (Join-Path $_.FullName 'scripts\Ensure-AndroidLabBroker.ps1')) } |
     Sort-Object { [version]$_.Name } -Descending
   ```
4. Check sanitized Lab status or lease-presence evidence first. If another active workflow may hold a lease, classify `broker_recovery_deferred` and require coordination. Otherwise invoke Stop, then Ensure. Suppress command output; never capture or print token-like values.
5. Poll `http://127.0.0.1:18190/health` with bounded backoff. Proceed only for JSON `status=ready`.
6. Increment `recoveryCount` to `1`, then call `android_lab_devices` and `android_lab_status` again. Treat `android_lab_status` as authoritative and reconcile any registry/runtime disagreement. If a lease existed, preserve the original reference; the first later side effect must use it, and invalid/not-owned becomes `lease_recovery_required` rather than a second acquire.

### 2. Broker healthy, MCP proxy still failing

If health is `ready` but the next MCP call still returns `fetch failed`, do not restart the Broker again. Classify `session_recovery_required`, release the lease safely, and tell the user to restart Codex. MCP catalogs and sessions are not hot-reloaded.

### 3. Emulator offline or starting

1. Select only an enabled no-credentials emulator, preferring `codex_api36`.
2. Acquire a lease before `android_lab_start`.
3. Read status. For `offline` or `starting`, call `android_lab_start` at most once for the current startup attempt and poll with bounded backoff.
4. Record the explicit state: `offline`, `starting`, `guest_boot`, `adb_unavailable`, `companion_not_ready`, `ready`, or `failed`.
5. `guest_boot` with `adbRegistered=false` is `adb_unavailable`; stop after the finite polling budget. Never call UI tools in that state. If the registry says `ready` while status says `offline` or `starting`, classify `registry_status_inconsistent` and use status for all gates.

### 4. Companion not ready

When `adbRegistered=true` but `companionReady=false`:

1. Read the registered `mcpPackage` from the sanitized device/status response.
2. Open that package with MCP `android_lab_open_app`.
3. Immediately call `android_lab_get_screen_state` for a fresh read.
4. Poll status until `companionReady=true` or the bounded timeout is reached.
5. If it remains unavailable, classify `companion_not_ready`; do not mask it as a generic timeout and do not use direct ADB. Only then consider the single Broker recovery, and only when the Companion launch or status reads failed.

### 5. APK missing

For a project Debug APK, require an explicit task-local mapping. A portable
invocation can provide:

```text
APK:    $env:TY_ANDROID_MCP_APK
Script: $env:TY_ANDROID_MCP_INSTALL_SCRIPT
Package: $env:TY_ANDROID_MCP_PACKAGE
```

If the mapping is not supplied, classify `project_apk_not_configured` and
stop; do not guess a path, package name, or installation command.

Resolve the APK and installer to canonical paths. Require regular files inside
the current project root, reject UNC paths and reparse points unless the user
explicitly authorized them, and inspect the installer to confirm it consumes
the exact APK path or accepts it as a literal argument. Invoke the reviewed
script with structured arguments, never shell-concatenated text. Otherwise
classify `project_installer_untrusted`.

1. After status is `ready`, call `android_lab_list_apps` (or the exact package-list tool exposed by the current catalog) to check installation. If no package-list MCP capability exists, stop with a missing-capability report; do not assume the APK is missing and do not install blindly.
2. If missing, record the APK SHA-256, run the existing reviewed project script for that exact APK while holding the lease, redact all output, and immediately fresh-read the screen. Do not add an ad-hoc ADB command.
3. Check package presence again through MCP. If still absent, classify `install_failed` and stop.
4. After any emulator or Broker restart, always repeat this check; never assume the APK, app process, session, or Companion state survived.

### 6. App has no launchable activity

1. Re-read status and require `ready`.
2. Re-check package installation once.
3. Retry `android_lab_open_app` at most once if the package is present.
4. If no launchable activity remains, classify `no_launchable_activity` and report the package and device id only. Do not loop or use a guessed activity name.

### 7. Launch and UI smoke

1. Open the package through MCP and immediately fresh-read the screen.
2. Find nodes from that fresh state. After every tap, type, replace, clear, swipe, scroll, Back/Home/Recents, install, launch, or intent, perform another fresh screen read and discard old node ids.
3. Use `type_replace_text` first and verify the final non-sensitive field value. Credential fields are blocked from all interaction and evidence.
4. Before `dismiss_keyboard`, prove an IME is present; after it, fresh-read and prove the IME disappeared. Use `BACK` for navigation only after proving no IME is open.

### 8. Release lease failure

1. Attempt normal `android_lab_release` in `finally` cleanup.
2. If it returns `fetch failed`, check Broker health once.
3. If health is `ready`, retry release once. If health is not ready, run no more than the single Broker recovery already allowed for this workflow, then retry release only if the session is valid.
4. If release still fails, classify `cleanup_failed`, preserve the lease id only as an internal redacted reference, and report the exact next manual action. Never kill processes or use direct ADB.

## Retry budget

- Maximum two attempts per transient Broker/network operation.
- Maximum one Broker Stop -> Ensure -> health recovery per workflow.
- `companion_not_ready` alone is not a Broker failure; launch Companion and poll first.
- A `catalog_mismatch` may consume the single recovery only before side effects and only to reload the configured installation. A persistent mismatch is not retried.
- No automatic retry for cancellation, 404, configuration errors, unknown/disabled devices, `no_launchable_activity`, or side effects on an invalid session.
- A failed recovery does not reset the counters. Stop and report the stage and category.

## Standard UI smoke

1. `android_lab_devices` and safe-device selection.
2. `android_lab_acquire`.
3. `android_lab_status`; start and recover only within the bounded rules above.
4. Ensure companion ready, open the requested app, and fresh-read.
5. Perform the smallest requested MCP UI action set with fresh postconditions.
6. Release the lease and record cleanup.

## Evidence at completion

Persist only the sanitized summary fields defined in `evidence-protocol.md`. Include recovery actions and counts so a later task can distinguish Broker failure, MCP session failure, emulator/ADB failure, companion failure, and APK/app failure. Without an explicit expected first-screen activity, resource, or text assertion, record only package/activity plus non-error fresh-read evidence and do not claim semantic UI acceptance.
