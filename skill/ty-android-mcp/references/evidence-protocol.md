# TY Android MCP Evidence Protocol

Use this compact, sanitized record for each Android automation batch. Save large artifacts outside chat only when they are explicitly allowed and scrubbed; never save raw UI trees, complete screenshots, image bytes, tokens, or private text.

```text
taskId: <stable task or batch id>
deviceId: <registered MCP device id>
apiLevel: <integer or unknown>
screenSize: <width>x<height or unknown>
devicePolicy: no_credentials|preserve_only|rejected
lease: acquired|conflict|released|cleanup_failed|not_required
startupPhase: offline|starting|guest_boot|adb_unavailable|companion_not_ready|ready|failed
registryStatusConsistency: consistent|inconsistent|unknown
bootCompleted: true|false|unknown
adbRegistered: true|false|unknown
companionReady: true|false|unknown
companionOpened: true|false|unknown|not_applicable
emulatorResidency: not_guaranteed|observed_running|unknown
session: fresh|reused|recovered|invalidated|session_recovery_required|not_applicable
packageInstalled: true|false|unknown|not_applicable
appOpened: true|false|unknown|not_applicable
freshRead: true|false|unknown|not_applicable
actions:
  - operation: <MCP operation name>
    inputClass: non_sensitive|credential_blocked|not_applicable
    precondition: <sanitized state>
    result: passed|failed|blocked
    postcondition: <fresh sanitized state>
providerRequestCount: <integer>
credentialRead: false|blocked|unknown
recoveryCount: <0 or 1>
recoveryActions: none|broker_stop_ensure_health|session_recovery_hint|release_retry|other_sanitized
failures: none|fetch_failed|session_recovery_required|catalog_mismatch|registry_status_inconsistent|adb_unavailable|companion_not_ready|project_apk_not_configured|missing_capability|install_failed|no_launchable_activity|lease_conflict|cleanup_failed|ui_state_mismatch|credential_blocked|environment_blocked
observedFailures: [<sanitized categories encountered and recovered during this workflow>]
cleanup: lease_released|lease_release_failed|not_required
nextStep: <one precise sanitized action>
unverified: <remaining risk>
```

## Acceptance rules

- A tool success message, screenshot, or model self-report cannot prove a UI mutation. Every write, install, launch, intent, navigation key, and keyboard transition needs a fresh post-action screen state.
- Every non-sensitive text input needs a final field-value check. Credential fields have no acceptable screenshot or OCR evidence.
- `bootCompleted=true` without `adbRegistered=true` and `companionReady=true` is an environment block, not a pass.
- When registry and runtime status disagree, record `registryStatusConsistency=inconsistent` and do not perform a side effect until a fresh runtime status resolves the state.
- `guest_boot` with missing ADB must be recorded as `adb_unavailable`; ADB registered with a missing companion must be recorded as `companion_not_ready`.
- Record at most one Broker recovery. A healthy Broker with a still-failing MCP proxy is `session_recovery_required` and requires a Codex restart.
- `providerRequestCount` must count only sanitized local test metadata. Do not include request bodies, headers, model output, image payloads, or credentials.

## Prohibited evidence

Never persist or report API Keys, Worker Keys, OAuth values, Authorization headers, DPAPI values, broker or lease tokens, Base64 payloads, image bytes, raw UI trees, complete screenshots containing sensitive content, or private session bodies. Keep lease identifiers and endpoint details redacted in user-facing records.
