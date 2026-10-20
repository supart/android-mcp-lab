# Android MCP Lab 0.1.3

Android MCP Lab 是面向 Codex 的 Windows Android Studio 模拟器控制层，派生自 `danielealbano/android-remote-control-mcp` v1.11.1 Companion。上游版本、固定提交、APK/证书 SHA-256、许可证和本地改动范围见 [UPSTREAM.md](UPSTREAM.md)。

稳定公开线提供受 lease 约束的本机模拟器控制链：

- 57 个固定版本的上游 Android 工具；
- 6 个 Global Lab 管理工具，用于设备发现、lease、启动、停止和状态查询；
- 稳定 `android_lab` catalog 共 63 个工具；
- canonical `ty-android-mcp` v0.2.0 自愈式 Skill。

Broker、stdio proxy、registry 和 Supervisor 仅在当前 Windows 用户环境内运行。本项目不修改 Android 系统镜像或业务应用源码。

## 版本与能力边界

| 项目 | 当前状态 |
| --- | --- |
| 稳定源码 | `0.1.3`，63 个工具 |
| canonical Skill | `ty-android-mcp` `0.2.0` |
| Mirror 预览分支 | `feature/mirror-realtime-0.1.3-preview.1`，66 个工具 |
| Mirror 真实视频 | `PROTOCOL_MOCK_ONLY`，尚未作为稳定能力发布 |
| public HEAD 与本机安装副本一致性 | `publicHeadInstallParity=pending` |

稳定线不包含实时模拟器视频。Mirror 预览只有在真实 Codex Browser WebRTC 首帧、持续播放、断线处理、TTL 到期和 lease 清理全部通过后，才可能升级为正式能力。

`publicHeadInstallParity=pending` 表示公开源码 HEAD 包含 0.1.3 维护性修订，但不能据此推断任意电脑上的 `install\0.1.3` 已同步到相同内容。使用者应通过 release 对应提交、manifest 和 SHA-256 确认实际安装版本。

## 从源码构建

环境要求：

- Windows 10/11 x64；
- PowerShell 7；
- Node.js 与 npm；
- 运行时需要 Android Studio、Android SDK、Android Emulator 和可用的 x86_64 虚拟化环境。

在仓库根目录执行：

```powershell
npm ci
npm run typecheck
npm run build
npm run build:bundle:dry-run
node .\tests\vnext-contract.mjs
pwsh -File .\tests\status-contract.ps1
```

这些命令只构建和验证 host 源码，不会启动 AVD、获取 lease、注册 Codex 或读取凭据。安装流程见 [START_HERE_FOR_CODEX.md](START_HERE_FOR_CODEX.md) 和 [docs/INSTALL.md](docs/INSTALL.md)。

## 基本运行流程

全局 MCP 名称为 `android_lab`：

```text
android_lab_devices
android_lab_acquire(codex_api36)
android_lab_status
android_lab_start(codex_api36)  # 仅当 status 不是 ready
android_lab_get_screen_state
android_lab_release(codex_api36)
```

`android_lab_status` 是 readiness 的权威来源。只有 `bootCompleted=true` 不代表可用；ADB 和 Companion 也必须 ready。每次 UI 写操作后必须重新读取 fresh screen state，状态变化后不得复用旧 node id。

## 设备与控制边界

- 只允许已登记的本机 Android Studio 模拟器。
- 普通自动化拒绝真机、局域网端点、未知 transport、禁用 AVD，以及标记为 `contains-credentials` 或 `preserve` 的设备。
- 不支持以 scrcpy、VNC、MJPEG、WebSocket 帧流、独立 ADB 或局域网控制作为旁路或降级方案。
- 所有副作用操作必须绑定有效 lease，并在成功、失败、取消和超时时执行 finally-style release。

## 源码与发行资产

Git 跟踪 host/Skill 源码、脚本、测试、文档、manifest、SHA-256 sidecar 和脱敏验证记录。以下内容不进入 Git：

- ZIP、APK、bundled Node、`node_modules`；
- AVD snapshot、runtime staging；
- Broker state、lease、session、日志和配置备份；
- 凭据、DPAPI 数据和私密内容。

历史 0.1.2/0.1.3 ZIP 保持原内容和 SHA-256，不由维护性提交静默重定义。后续二进制应作为 GitHub Release 资产发布，并绑定准确提交、manifest 和 SHA-256 sidecar。

## 安全

API Key、OAuth、Authorization、Worker Key、DPAPI、Broker/lease token、私密会话正文、敏感 UI tree、图片字节和敏感截图不得进入源码、日志、验证证据或发行资产。完整规则见 [SECURITY.md](SECURITY.md)。

## English Summary

Android MCP Lab 0.1.3 is a Windows/Codex host layer for registered local Android Studio emulators. The stable catalog has 63 tools and uses the `ty-android-mcp` v0.2.0 Skill. The separate 66-tool Mirror branch remains `PROTOCOL_MOCK_ONLY`. Physical devices, LAN control, scrcpy, VNC, and independent-ADB bypasses are out of scope. Binary assets and machine state are not stored in Git. `publicHeadInstallParity` remains `pending`; verify release assets against their exact commit, manifest, and SHA-256 before installation.
