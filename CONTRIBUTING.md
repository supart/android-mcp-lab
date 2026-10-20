# 贡献指南

Android MCP Lab 采用小范围、可审阅、可验证、可回滚的改动。公开稳定线当前为 `0.1.3`、63 个工具；canonical Skill 为 `ty-android-mcp` v0.2.0。

## 分支与改动范围

1. 从稳定公开线创建名称明确的 feature branch。
2. host/Skill 修改与 Companion native 修改必须分开。
3. Mirror 实验保留在 `feature/mirror-realtime-0.1.3-preview.1`。该分支有 66 个工具并保持 `PROTOCOL_MOCK_ONLY`；未经独立发行决策，不得把 3 个 Mirror 工具合入稳定 63 工具 catalog。
4. Companion native 修复必须使用新的 APK 版本/构建标识和独立验证，不能原地替换固定的 v1.11.1 基线。
5. 不重写冻结的 0.1.2/0.1.3 artifact 历史。未来二进制应作为绑定准确提交的 GitHub Release 资产发布。

## 可移植性要求

- 干净克隆必须仅依赖仓库声明的依赖完成安装、typecheck 和 build。
- 不得依赖其他应用工作区、`node_modules` junction、本机绝对路径或未声明工具。
- Skill 示例使用通用变量或显式参数，不写入维护者本机项目路径。
- `publicHeadInstallParity=pending` 期间，不能把公开 HEAD 描述为已自动同步到任意既有安装副本。

## 禁止提交的内容

- API Key、OAuth、Authorization、Worker Key、DPAPI、token 或私密会话数据；
- 本机配置备份、Broker state、lease、session、日志或 AVD snapshot；
- APK、ZIP、bundled runtime、runtime staging 或 `node_modules`；
- 敏感截图、图片字节、Base64 payload 或未脱敏 UI tree。

## 提交前检查

按改动范围至少运行：

```powershell
npm ci
npm run typecheck
npm run build
npm run build:bundle:dry-run
node .\tests\vnext-contract.mjs
pwsh -File .\tests\status-contract.ps1
```

同时检查：

- PowerShell AST parse；
- Skill validation；
- manifest/sidecar JSON parse；
- Git tracked-file 敏感信息扫描；
- 绝对路径和工作区外依赖扫描；
- `git diff --check`。

提交信息应能区分 runtime 行为、公开树整理、文档和 release 资产。不要把构建通过写成模拟器运行通过。

## 支持边界

稳定线仅支持本机 Android Studio 模拟器。不接受以真机、局域网控制、scrcpy、VNC、MJPEG、WebSocket 帧流或独立 ADB 绕过 lease 与 MCP 安全边界的贡献。

## English Summary

Keep changes small and reviewable. Separate host/Skill work, companion-native work, and the 66-tool Mirror preview. A clean clone must build without external workspaces or machine-specific paths. Never commit binaries, runtime state, credentials, private data, or sensitive evidence. Run the listed checks and publish future binaries as release assets tied to an exact commit.
