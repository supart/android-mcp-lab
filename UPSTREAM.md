# 上游来源与派生说明

Android MCP Lab 是上游 Android MCP Companion 的派生 host/integration 项目，不应描述为完全原创的 Android MCP 实现。

## 固定上游基线

- 上游仓库：<https://github.com/danielealbano/android-remote-control-mcp>
- 固定 release：`v1.11.1`
- 固定 release commit：`2b87d46e91421295cd4893185b694612ec2c94d1`
- 上游许可证：MIT
- 固定 Companion 变体：`android-remote-control-mcp-v1.11.1-foss-release.apk`
- Android package：`com.danielealbano.androidremotecontrolmcp`
- APK SHA-256：`39fbe125840ebd68eb8c6af7c509f1e8e65ed61f0890f841e29bf83830f3c581`
- 签名证书 SHA-256：`2c44a5870e8a222bf790d45843fd57391e01f28212adea8c50ccce2d68dc2d4b`

APK 和证书哈希同时由 package manifest 与 host 脚本固定。任何 Companion native 修改都必须使用新的 APK 版本/构建标识和独立分支，不得原地覆盖 v1.11.1 基线。派生发布必须保留上游版权和 MIT 许可证声明。

## 本地增强范围

本仓库围绕固定 Companion 增加 Windows/Codex host 层：

- Broker 与 stdio proxy 生命周期；
- 多 AVD registry、serial allow-list 和 lease ownership；
- session recovery 与 `catalog_mismatch` 处理；
- Supervisor startup phase 和 `adb_unavailable` 分类；
- 真机拒绝与 loopback emulator routing；
- Codex 全局 `android_lab` 注册和 Bootstrap；
- `ty-android-mcp` v0.2.0 自愈式 Skill 与脱敏证据流程。

稳定公开线为 `0.1.3`，暴露 63 个工具：57 个上游 Android 工具和 6 个 Global Lab 管理工具。

Companion native 的 `type_clear_text` 和 `dismiss_keyboard` 实现没有被本仓库修改。Skill 与 Bridge 只执行 postcondition 检查和失败分类，不能冒充 native 修复。

## Mirror 预览边界

`feature/mirror-realtime-0.1.3-preview.1` 增加 3 个实验性 Mirror 控制面工具，因此 catalog 为 66 个。它仍是 `PROTOCOL_MOCK_ONLY`；在真实 Codex Browser WebRTC 首帧和完整生命周期回归通过前，不属于稳定 0.1.3 能力。

Mirror 不允许降级到 scrcpy、VNC、MJPEG、WebSocket 帧流、独立 ADB 或局域网控制。

## 分发边界

上游审计通过 `upstream` Git remote 和固定 release metadata 进行。APK、ZIP、bundled runtime 与本机 state 不进入 Git 历史。二进制应作为绑定准确源码提交的 GitHub Release 资产发布，并附 manifest 与 SHA-256 sidecar。

当前 `publicHeadInstallParity=pending`：公开 HEAD 的维护性修订不自动证明任意本机 `install\0.1.3` 已同步。发行和验收记录必须明确区分源码提交、release asset 与实际运行副本。

## English Summary

Android MCP Lab is derived from `danielealbano/android-remote-control-mcp` v1.11.1 under the MIT License. The stable 0.1.3 line combines 57 pinned upstream tools with 6 Global Lab management tools. Local additions cover the Windows/Codex Broker, proxy, AVD registry, leases, recovery, Bootstrap, and Skill v0.2.0. The 66-tool Mirror branch remains `PROTOCOL_MOCK_ONLY`; binaries and machine state stay outside Git.
