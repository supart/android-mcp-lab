# Verification Evidence Index

This directory contains sanitized, reproducible evidence for Android MCP
Global Lab. It is documentation, not a runtime state directory.

## Current Stable Evidence

- `public-repo-20261019.json` records the public-source cleanup checks. It is
  source validation evidence only; it is not a new Android runtime pass. Its
  `SOURCE_AND_INSTALL_VERIFIED` value applies to the existing stable baseline;
  public-HEAD Skill installation parity remains explicitly pending.
- `android-mcp-global/RESULTS.md` contains dated stable-line results. Later
  maintenance does not convert those historical runs into a new runtime pass.
- `android-mcp-global/vnext-20260822.json` is the compact stable status record.
  Its `SOURCE_AND_INSTALL_VERIFIED` state and pending items remain explicit.
- `android-mcp-global/bootstrap/` contains sanitized acceptance summaries. It
  contains no local credentials or reusable runtime state.

## Historical Evidence

`summary.json`, `timeout-diagnosis.md`, the bootstrap JSON files, and older
sections of `RESULTS.md` preserve earlier package and failure evidence. Version
numbers and dates in those files are historical, not the current active
runtime. Local user, SDK, and installation paths use environment variables or
workspace-neutral descriptions.

## Mirror Preview

The stable branch has 63 tools and does not claim real-time browser mirroring.
Mirror preview evidence belongs to its separate preview branch and remains
`PROTOCOL_MOCK_ONLY` until a real browser WebRTC first frame and lifecycle
regression are complete. A gRPC screenshot frame alone is not continuous
browser video evidence.

## Files Kept Out Of Git

Local configuration backups, lease/session/state directories, broker logs,
screenshots, APKs, ZIPs, bundled runtimes, AVD snapshots, and credential
material are excluded by repository ignore rules. Release binaries may be
published later as external release assets with a commit reference and
SHA-256 sidecar; they are not stored in the source history.

## Redaction Rules

Evidence may record device aliases, versions, status classifications, hashes,
tool counts, and sanitized error categories. It must never record API keys,
OAuth or Authorization values, DPAPI material, broker/lease tokens, Base64,
private session text, raw UI trees, image bytes, or complete sensitive
screenshots.
