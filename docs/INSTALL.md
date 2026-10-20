# 安装 Android MCP Lab 0.1.3

Android MCP Lab 0.1.3 是面向 Windows 本机 Android Studio 模拟器的稳定 63 工具控制链，配套 canonical `ty-android-mcp` v0.2.0 Skill。Mirror 是独立的 66 工具预览实验，仍为 `PROTOCOL_MOCK_ONLY`，本指南不会安装它。

## 环境要求

- Windows 10/11 x64；
- PowerShell 7；
- Android Studio 与 Android SDK；
- API 36 Google APIs x86_64 组件，或允许 `sdkmanager` 下载这些固定组件；
- Android Emulator 所需的硬件虚拟化；
- Codex Desktop。

Android Studio 首次登录、许可证确认和 SDK 下载确认由用户手动完成。

## 安装已验证的 Release

每个版本目录应只放对应版本的三件套：

```text
Android-Mcp-Lab-0.1.3.zip
Android-Mcp-Lab-0.1.3.sha256
Android-Mcp-Lab-0.1.3-manifest.json
```

解压前校验 ZIP：

```powershell
Get-FileHash .\Android-Mcp-Lab-0.1.3.zip -Algorithm SHA256
```

将结果与 sidecar 比较。解压后先运行不修改全局配置的验证：

```powershell
pwsh -File .\scripts\Invoke-CodexAndroidMcpBootstrap.ps1 `
  -OfflineBundle . `
  -Mode Validate `
  -RegisterGlobalConfig:$false
```

验证通过后正式安装：

```powershell
pwsh -File .\scripts\Invoke-CodexAndroidMcpBootstrap.ps1 `
  -OfflineBundle . `
  -Mode Auto `
  -RegisterGlobalConfig
```

随后重启 Codex。全局 MCP 名称为 `android_lab`。

不要在电脑之间复制 AppData state、lease、session、日志、AVD snapshot、`node_modules`、配置备份或任何凭据。

> `publicHeadInstallParity=pending`：源码 HEAD 的维护性变更不自动同步到既有 `install\0.1.3`。安装证据应同时记录 release 对应提交、manifest、ZIP SHA-256、重启后工具数量和 runtime 状态。

## 从源码构建

```powershell
npm ci
npm run typecheck
npm run build
npm run build:bundle:dry-run
```

源码构建不会自动包含固定 Companion APK 或 bundled Node。只有显式调用完整打包脚本并提供本地 release 输入时才会生成二进制包；完整脚本拒绝覆盖已存在的版本目录。ZIP、APK 和 bundled runtime 均不进入 Git。

## 运行 Smoke

只使用已登记的 no-credentials 模拟器：

```text
android_lab_devices
android_lab_acquire(codex_api36)
android_lab_status
android_lab_start(codex_api36)  # 仅在需要时
android_lab_status
android_lab_get_screen_state(codex_api36)
android_lab_release(codex_api36)
```

正常 smoke 不调用 `android_lab_stop`，不使用 direct ADB 点击、输入或截图。真机、局域网设备、scrcpy、VNC 和独立 ADB 旁路不在支持范围内。

## 卸载

```powershell
pwsh -File .\scripts\Uninstall-AndroidMcpLab.ps1
```

脚本按选项移除全局 MCP 注册、Broker 安装、Companion 安装和已安装 Skill，不得删除无关 AVD、Android SDK 或用户项目。

## 失败分类

- guest 已启动但 ADB 不可见：`adb_unavailable`；
- ADB 已登记但 Companion 未 ready：`companion_not_ready`；
- catalog 数量、prefix 或 schema 不一致：`catalog_mismatch`；
- Broker 健康但 MCP proxy session 失效：`session_recovery_required`；
- 预览视频端点不可用：`mirror_endpoint_unavailable`。

不得把这些状态改写为普通超时或成功。

## English Summary

Install only a verified Android MCP Lab 0.1.3 release triplet, run Validate before Auto Bootstrap, and restart Codex afterward. The stable runtime has 63 tools and uses Skill v0.2.0. The 66-tool Mirror preview remains `PROTOCOL_MOCK_ONLY`. Do not transfer machine state or credentials between computers, and do not use physical devices, LAN control, scrcpy, VNC, or independent ADB bypasses.
