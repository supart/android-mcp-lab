# Android MCP Lab 0.1.3：Codex 从这里开始

本文面向需要安装或验收稳定 63 工具控制链的 Codex。canonical Skill 为 `ty-android-mcp` v0.2.0。Mirror 预览不由本流程安装，其 66 工具分支仍是 `PROTOCOL_MOCK_ONLY`。

开始前阅读 [安装说明](docs/INSTALL.md)、[上游来源](UPSTREAM.md) 和 [安全策略](SECURITY.md)。

> 当前 `publicHeadInstallParity=pending`。公开源码 HEAD 与某台电脑上的既有 `install\0.1.3` 不应被默认视为逐文件一致；安装和验收必须以 release 对应提交、manifest、SHA-256 及重启后的实际工具目录为准。

## 1. 验证源码克隆

在仓库根目录执行：

```powershell
npm ci
npm run typecheck
npm run build
npm run build:bundle:dry-run
node .\tests\vnext-contract.mjs
pwsh -File .\tests\status-contract.ps1
```

这只验证 host 源码，不会修改全局 Codex 配置、启动模拟器、获取 lease 或读取凭据。

## 2. 安装已验证的发行包

从已解压且完成哈希校验的 0.1.3 bundle 中先执行只读验证：

```powershell
pwsh -File .\scripts\Invoke-CodexAndroidMcpBootstrap.ps1 `
  -OfflineBundle . `
  -Mode Validate `
  -RegisterGlobalConfig:$false
```

验证通过后执行 Bootstrap：

```powershell
pwsh -File .\scripts\Invoke-CodexAndroidMcpBootstrap.ps1 `
  -OfflineBundle . `
  -Mode Auto `
  -RegisterGlobalConfig
```

Bootstrap 会尽量复用 Android Studio SDK，只安装所需的固定 API 36 组件，按需创建无凭据专用 AVD `codex_api36`，安装固定 Companion 和 canonical Skill，并注册用户级 `android_lab` MCP。

安装或配置变化后必须重启 Codex。MCP 和 Skill catalog 不支持热加载，重启前的工具结果不能作为验收证据。

## 3. 设备安全规则

- 优先使用 `codex_api36`，或用户明确指定且已登记的 no-credentials 模拟器。
- 拒绝真机、局域网端点、未知/禁用设备、不支持的 API/ABI，以及标记为 `contains-credentials` 或 `preserve` 的设备。
- Android Studio/Gemini 与 Codex 自动化默认使用不同 AVD。
- 安装、启动应用、UI 操作或测试前必须 acquire lease，并在所有退出路径执行 finally-style release。
- 不使用 direct ADB UI 命令、scrcpy、VNC、独立 ADB 或其他旁路作为 fallback。

## 4. 重启后的运行验收

```text
android_lab_devices
android_lab_acquire(codex_api36)
android_lab_status
android_lab_start(codex_api36)  # 仅当 status 不是 ready
android_lab_status
android_lab_get_screen_state(codex_api36)
android_lab_release(codex_api36)
```

验收至少要求：

- 稳定 catalog 为 63 个工具；
- `startupPhase=ready`；
- `bootCompleted=true`；
- `adbRegistered=true`；
- `companionReady=true`；
- fresh screen read 成功；
- lease 成功释放且无遗留。

`android_lab_status` 是 readiness 权威来源。`guest_boot` 不能当作 ready。每次 UI 写操作后必须 fresh-read，并禁止复用旧 node id。

## 5. 自愈边界

Skill 允许一次有界 Broker 恢复。若 Broker health 已为 ready，但 Codex MCP proxy 在恢复后仍持续返回 `fetch failed`，必须停止自动化，分类为 `session_recovery_required`，并要求用户重启 Codex，不能无限重试。

`adb_unavailable`、`companion_not_ready`、`catalog_mismatch` 和 `session_recovery_required` 必须分别记录，不得被改写为笼统超时或成功。

## 6. 发行边界

Git 仓库不包含 release ZIP、APK、bundled Node、runtime state、lease、session、日志、AVD snapshot、配置备份或凭据。二进制只能从绑定准确源码提交的 release 获取，并在 Bootstrap 前校验发布的 SHA-256。

## English Quick Start

Validate a clone with `npm ci`, typecheck, build, bundle dry-run, and the contract tests above. Install only a verified 0.1.3 release bundle, restart Codex, then run the lease-bound acceptance sequence against a registered no-credentials emulator. The stable catalog has 63 tools; Mirror is a separate 66-tool `PROTOCOL_MOCK_ONLY` preview. Persistent proxy failure after one recovery requires a Codex restart.
