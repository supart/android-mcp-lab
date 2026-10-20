# 安全策略

## 适用范围

Android MCP Lab 通过 loopback Broker 和 Codex `android_lab` MCP 控制已登记的本机 Android Studio 模拟器。它不是局域网远程控制服务，也不得把真机或未知 transport 选为操作目标。

稳定 0.1.3 catalog 有 63 个工具，配套 `ty-android-mcp` v0.2.0。独立 Mirror 预览有 66 个工具，但仍是 `PROTOCOL_MOCK_ONLY`，不能视为已验收的实时视频安全边界。

## 受保护数据

不得输入、复制、持久化、记录或公开：

- API Key、OAuth、Authorization header、Worker Key 或其他凭据；
- DPAPI 值、Broker token、lease token 或私密 session 正文；
- 含凭据的 UI tree、图片字节、Base64 payload 或敏感截图；
- 本机 runtime state、lease、session、日志、配置备份、AVD snapshot 或私有项目数据。

标记为 `contains-credentials` 或 `preserve` 的设备不得用于普通自动化。

## 控制边界

- Broker 和相关 transport 只绑定 loopback。
- 每个副作用操作都必须持有有效 lease。
- Android UI 操作只通过 `android_lab`；禁止 direct ADB UI 命令。
- 拒绝真机、局域网端点、未知 transport、禁用 AVD 和不支持的 API/ABI。
- 不使用 scrcpy、VNC、MJPEG、WebSocket 帧流、独立 ADB 或局域网访问作为 Mirror fallback。
- 预览视频不可用时必须返回 `mirror_endpoint_unavailable`，不得生成假 endpoint 或伪造首帧。
- `publicHeadInstallParity=pending` 时必须区分源码 HEAD、release asset 和实际安装副本，不能把版本号相同当作内容相同。

## 漏洞报告

不要在公开 issue 中提交 secret、原始 session 数据、敏感截图或 runtime dump。报告应只保留脱敏复现步骤、受影响版本、失败分类和恢复影响，并通过仓库维护者提供的私密安全渠道提交。若尚无私密渠道，只发布不含敏感数据的最小通知，等待维护者建立私密联系。

## Release 门禁

每个源码 release 至少通过：

- tracked-file 敏感信息扫描；
- 绝对路径和外部依赖扫描；
- manifest 与 SHA-256 校验；
- PowerShell parse；
- TypeScript typecheck/build；
- Skill validation；
- 相关 contract tests。

guest boot 但 ADB 未登记必须分类为 `adb_unavailable`；ADB 已登记但 Companion 未 ready 为 `companion_not_ready`；Broker 健康但 proxy session 失效为 `session_recovery_required`。这些失败不得被普通超时掩盖。

## English Summary

Android MCP Lab is loopback-only and targets registered local emulators. Never select physical devices, LAN endpoints, credential-bearing devices, or preserve-only devices. Never publish credentials, tokens, private sessions, sensitive UI evidence, or machine state. Direct ADB UI control, scrcpy, VNC, independent ADB, and network fallbacks are prohibited. Report security issues through a private channel with sanitized evidence.
