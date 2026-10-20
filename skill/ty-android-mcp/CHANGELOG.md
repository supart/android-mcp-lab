# ty-android-mcp Changelog

## 0.2.0 - 2026-08-30

- Added bounded self-healing startup for Broker, emulator, Companion, project APK installation, and lease cleanup.
- Made `android_lab_status` authoritative for runtime readiness when it conflicts with the device registry.
- Added explicit `registry_status_inconsistent` and `emulatorResidency` evidence fields.
- Changed `companion_not_ready` recovery to launch the registered Companion package before considering Broker recovery.
- Documented that the emulator is supervisor-managed and package/app state must be rechecked after restarts.
- Added a single Broker Stop -> Ensure -> health recovery boundary and a Codex restart boundary for persistent MCP proxy failures.
- Replaced machine- and project-specific APK paths with task-local `TY_ANDROID_MCP_APK`, `TY_ANDROID_MCP_INSTALL_SCRIPT`, and `TY_ANDROID_MCP_PACKAGE` inputs.

No provider credentials, model requests, image bytes, raw UI trees, or private session text are stored by this Skill.
