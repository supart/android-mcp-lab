# Device Policy

## Selection order

1. Use an explicitly named enabled emulator only when it is listed by `android_lab_devices` and marked no-credentials.
2. Otherwise prefer the registered `codex_api36` no-credentials AVD.
3. Otherwise select another enabled no-credentials emulator and report the selected device id.
4. Reject devices marked `contains-credentials` or `preserve` for ordinary work, plus physical devices, LAN endpoints, disabled devices, unknown serials, and ABI/API-incompatible AVDs. Never infer safety from a friendly display name.

The device id is an MCP registry identifier, not a raw ADB target. Do not print or persist serials, SDK paths, host paths, or transport details.

## Runtime status precedence

- `android_lab_devices` establishes registration, credential policy, and whether a device is allowed for the task.
- `android_lab_status` establishes the current emulator, ADB, Companion, and MCP session state. It is authoritative for readiness.
- If the two responses disagree, classify `registry_status_inconsistent`, discard the stale runtime snapshot, and perform one bounded fresh status read before any write, install, launch, or UI action.
- `bootCompleted=true` alone never permits UI work. Require `adbRegistered=true` and `companionReady=true`.

## Lease lifecycle

- Acquire exactly one lease before UI writes, installation, app launch, file writes, or test actions.
- Keep the lease for the complete workflow and release it in `finally` cleanup after success, failure, timeout, cancellation, interruption, and process exit.
- If acquisition reports a conflict, report the owner category and stop; do not blindly retry.
- If the MCP session is invalidated while a lease is held, perform the single allowed Broker/session recovery, re-read device/status, and release the original lease id during cleanup. Do not acquire a second lease as a workaround.
- If release returns `fetch failed`, check Broker health and retry release once only when health is `ready`; otherwise classify `cleanup_failed`.

## Broker recovery boundary

For `fetch failed`, `session_recovery_required`, `catalog_mismatch`, or `adb_unavailable`, the Skill may perform one Stop -> Ensure -> `http://127.0.0.1:18190/health` recovery. `companion_not_ready` must first be handled by opening the registered Companion package through MCP and polling status; do not restart the Broker merely because Companion is not running. Discover the installation dynamically under `%LOCALAPPDATA%\WhiteCodex\AndroidMcpLab\install\*`, locating both official scripts under `scripts`. A healthy Broker does not prove the current Codex MCP proxy session is healthy; persistent proxy failure requires a Codex restart.

## Emulator residency

The AVD is supervisor-managed and is not guaranteed to remain resident across Codex, Broker, or emulator restarts. After a restart, re-check status, Companion readiness, package installation, and app launchability. Do not assume APKs, app processes, or session state survived.

## Readiness and input gates

- `bootCompleted=true` is not sufficient. Require `adbRegistered=true` and `companionReady=true` before UI actions.
- `guest_boot` with missing ADB is `adb_unavailable`; ADB registered with a missing companion is `companion_not_ready`.
- Every successful input call must be followed by a fresh screen read; every non-sensitive text input must be checked against the final field value.
- Credential fields are always `credential_blocked`: no typing, clipboard, OCR, screenshots, persistence, or model echo for API keys, OAuth, Authorization, DPAPI, Worker Keys, tokens, or private session bodies.
- `BACK` is navigation, not a keyboard workaround. Use it only after a fresh state read proves that no IME window is open. `dismiss_keyboard` requires an observed IME and a postcondition proving it disappeared.

## Preserve-only devices

Any registered device marked `contains-credentials` or `preserve` is preserve-only. Clearing data, uninstalling packages, or destructive instrumentation requires an explicit force request naming the device and a second confirmation that repeats the exact device id and acknowledges irreversible data loss. Never encode a user-specific device id or confirmation phrase in the public Skill.

Never include screen content, key material, authorization headers, or token values in reports.

## Test devices

Use `codex_api36` or another explicitly registered no-credentials test AVD for reinstall, clear-data, and instrumentation workflows. Keep Android Studio Gemini on a different AVD from Codex automation. Do not connect physical or LAN devices.
