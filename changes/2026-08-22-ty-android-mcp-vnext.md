# TY Android MCP vNext 编排与 Global Lab 兼容性修复

## 状态

2026-08-22 完成第一批 vNext 优化。目标是把 `$ty-android-mcp` 从自然语言步骤说明提升为可审计的 Android 自动化工作流，并让 Global Lab 对 session、catalog、AVD 启动状态和 lease cleanup 提供结构化边界。

## 已完成

- Skill 增加写操作后的 fresh screen state 硬门槛，禁止复用旧 node id；
- 文本输入默认 replace 并校验字段值，非敏感字段才允许 clipboard fallback；
- credential fields、API Key、OAuth、Authorization、DPAPI 和私有会话正文统一禁止自动化输入、复制、截图和持久化；
- IME 关闭与页面 Back 分离，`dismiss_keyboard` 后必须复核窗口状态；
- Skill 增加 `evidence-protocol.md`，固定设备、lease、startup、session、postcondition、failure 和 cleanup 记录；
- Supervisor status 增加 `startupPhase`、`bootCompleted`、`adbRegistered`、`companionReady`、`processId`、端口、SDK 根目录、Emulator 版本、日志位置和脱敏 failure；
- guest boot 但 ADB 未注册分类为 `adb_unavailable`；旧日志只有在 Emulator 进程仍存在时才参与该判断；
- Broker catalog 不匹配返回 `catalog_mismatch`；上游 session 失效区分只读重连与副作用操作不重试；
- stdio proxy 增加 Broker session 自动重建、通用 lease tracking、stdin/SIGINT/SIGTERM cleanup 和释放失败摘要；
- 新增 vNext contract test，覆盖 Skill 规则、catalog mismatch、session recovery、side-effect retry block 和 lease cleanup。

## 未闭合

- 当前运行中的全局 MCP 仍需 Codex 重启后加载新安装副本；本批不强制重启正在执行的 DSH Mobile 任务；
- `0.1.2` 离线 ZIP 尚未重打包，版本基线保持不变；
- 当前主机 `codex_api36` 的 guest boot/ADB transport 现场仍需后续独立回归；
- 第二台 Windows、隐式 Skill 触发和真实取消/stdio close 回归尚未完成；
- companion 层 `type_clear_text`、`dismiss_keyboard` 的底层实现尚未修改，本批先在 Skill 编排层强制复核。

## 安全与边界

- 未读取、输入或记录任何 API Key、OAuth、Authorization、DPAPI 或用户会话正文；
- 未使用 direct ADB UI 控制；
- 未修改外部业务项目、AVD ABI、PRoot 或 Android 系统镜像；
- preserve 设备仍禁止强制停止；arm64/x86_64 阻塞不伪造成功。

## 验证入口

```powershell
node --import tsx/esm tests/vnext-contract.mjs
```

随后同步当前用户安装副本并在安全的 Codex 重启窗口运行 `Config`、lease smoke 和冷启动回归。
