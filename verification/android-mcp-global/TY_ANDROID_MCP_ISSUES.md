# TY Android MCP 通用开发问题清单

更新日期：2026-08-22

2026-08-22：vNext 第一批已落盘并同步到 0.1.2 安装副本。已直接修复 Skill、Broker/stdio 和 Supervisor 的兼容行为；底层 companion 的输入实现仍保持只读，下一次若取得 companion 源码或新 APK，应继续修复 TY-005/TY-006 原生实现，不能把桥接层门禁当作 native 已修复。
2026-08-22：补充修复 ADB transport 解析。无关物理 transport 不再阻断注册 emulator 的 status/启动解析；任何物理 serial 仍不在允许目标集合内，也未被本批操作。
2026-08-22：源码活动入口已迁移到根目录 `android-mcp-lab/`；`development/android-mcp-lab/` 保留为冻结快照。迁移不改变 MCP schema、安装副本、ZIP 版本或安全边界。
2026-08-22：根目录源码收口静态复核通过；关键哈希、typecheck、PowerShell AST、vNext/status contract、Config、JSON 和敏感扫描均通过。当前 lease 目录有一个外部 lease，本批未触碰；真实 Codex 重启 smoke 继续 pending。

## 记录规则

- 只记录可复现、会影响通用 Android 开发工作流的问题。
- 每项必须包含复现条件、影响、当前状态、修复或恢复方法、验证证据。
- 不记录 API Key、Token、Authorization、DPAPI 密文、用户会话正文或含凭据画面。
- Emulator、ADB、Broker、stdio session、lease、companion 和 Skill 编排问题分开归因。

## 当前问题

### TY-001：Broker 重载后旧 stdio MCP session 失效

- 复现：安装版 Broker 或代理进程重启后，当前 Codex 任务继续复用旧 `android_lab` session。
- 表现：`Invalid or missing MCP session` 或 `Transport closed`。
- 影响：Skill 虽能被触发，但所有 Global Lab 工具不可用；容易被误判为设备或 AVD 故障。
- 当前状态：已确认；本批次使用 fresh stdio 客户端继续诊断。
- 通用工具要求：代理应支持 session 自动重建，或稳定返回明确的“需要重载 MCP/Codex”恢复指引。
- 证据：参考 Compose 测试应用的脱敏运行记录。

### TY-002：`android_lab_stop` 的 Supervisor 输出不是 JSON

- 复现：Broker 调用 `Invoke-AndroidLab.ps1 -Action down`。
- 表现：设备停止动作执行后，Broker 对 `Android MCP stopped: <id>` 执行 `JSON.parse` 并报错。
- 影响：调用者无法判断 stop 是否成功，可能重复执行恢复动作。
- 当前状态：源码和本机 `0.1.2` 安装副本已修复为单行 JSON。
- 通用工具要求：所有 Supervisor 内部动作必须使用一致、可机器解析的单行 JSON 协议。
- 验证：PowerShell AST parse 通过；fresh stdio `android_lab_stop` 返回 `status=stopped`。

### TY-003：ADB 未注册时非 preserve AVD 无法通过 Lab 停止

- 复现：AVD 已存在有效 emulator/qemu lock PID，但 `adb devices` 中没有 serial。
- 表现：旧 `Stop-LabDevice` 只在发现 serial 时停止实例，否则静默不处理。
- 影响：兼容参数修复、冷启动回归和故障恢复被卡住，只能绕开 Lab 结束进程。
- 当前状态：源码和本机 `0.1.2` 安装副本已增加受保护恢复分支；仅对 `dataPolicy != preserve` 的设备，根据有效 emulator/qemu lock PID 停止失联实例。
- 通用工具要求：恢复路径必须同时校验设备数据策略、AVD 身份和进程类型；`preserve` 设备不得使用强制结束回退。
- 验证：`openminis_api36` 失联实例已通过 fresh stdio `android_lab_stop` 停止；未操作 `dsh_api36`。

### TY-004：Emulator 37.1.11 客体启动完成但传统 ADB transport 未注册

- 复现：Windows 10 x86_64、Android Emulator `37.1.11.0` build `15917651`、API 36 x86_64 AVD，Global Lab 指定固定 emulator port。
- 表现：Emulator 日志约 30 秒出现 `Boot completed`，但预期的 console/ADB 端口未监听，`adb devices` 无 `emulator-<port>`，Lab `status=starting`、`bootCompleted=false`。
- 已排除：SDK 根目录错误、ADB server 未启动、AVD ABI/系统镜像不支持、启动参数未传入。
- 当前状态：调查中；`-port` 和 `-no-direct-adb` 未恢复注册，正在验证显式 `-ports <console>,<adb>` 兼容路径。
- 通用工具要求：启动器应记录 Emulator/ADB 版本、实际 PID、预期端口、启动阶段和脱敏失败摘要；对已完成 guest boot 但未注册 transport 的状态应单独分类。
- 证据：`%LOCALAPPDATA%/WhiteCodex/AndroidMcpLab/logs/emulator-openminis_api36.stdout.log` 和本文件对应批次记录。

### TY-005：`type_clear_text` 成功状态与实际字段值不一致

- 复现：参考 Compose 测试应用的 `EditText` 初始值为普通非敏感文本，调用 `android_lab_type_clear_text`。
- 表现：工具返回“Text cleared”，但同一返回中的 `Field content` 仍为 `OpenAI`；后续追加 `FHL` 产生错误混合文本。
- 影响：Skill 若只判断调用无错误，会把错误配置写入应用；对 Provider、URL、模型等表单均有风险。
- 当前状态：已确认，companion 层尚未修复；本批次改用 `type_replace_text`，并强制校验返回的最终字段内容。
- 通用工具要求：文本变更工具应在动作后重新读取目标字段，并在期望状态未达成时返回错误；Skill 编排必须把返回字段值作为成功门槛。

### TY-006：`dismiss_keyboard` 返回后 IME 仍可能保持打开

- 复现：在参考 Compose 测试表单完成 `type_append_text` 后调用 `android_lab_dismiss_keyboard`。
- 表现：调用无错误，但后续 screen state 仍包含 Gboard `INPUT_METHOD` 窗口，表单下半部分节点因可视区域缩小而消失。
- 影响：Skill 后续使用旧 node id 会报 `node not found`，也可能把关闭键盘误当成页面已稳定。
- 当前状态：已确认；本批次在确认 IME 窗口存在后通过 MCP `press_key BACK` 关闭，再重新获取 screen state。
- 通用工具要求：`dismiss_keyboard` 应在返回前验证 IME 窗口已消失；Skill 应在表单继续前重新读取屏幕，不复用键盘切换前的 node id。

### TY-007：Compose 空字段可能在首字符失去 InputConnection

- 复现：对参考 Compose 测试表单的空白 `EditText` 调用 `type_append_text` 输入普通非敏感 URL。
- 表现：工具在 `position 0 of 19` 报 `Input connection lost during verification`，屏幕复查字段仍为空。
- 影响：同一表单中短标签可成功、URL 字段却失败，不能仅凭控件类型推断输入能力。
- 当前状态：已确认；本批次只对非敏感 URL 使用 MCP 设置剪贴板并走系统粘贴菜单。API Key 仍禁止进入剪贴板或自动化输入。
- 通用工具要求：输入失败必须保留字段原值并返回可分类错误；Skill 应提供非敏感文本的 MCP 剪贴板粘贴回退，但凭据字段必须明确禁用该回退。

### TY-008：无状态 `BACK` 键盘回退可能误触页面导航

- 复现：系统粘贴菜单动作完成后，未重新读取窗口状态就立即调用 MCP `press_key BACK`。
- 表现：若 IME/弹窗已自行消失，`BACK` 会落到测试应用导航栈并退回上一页。
- 影响：未保存的表单状态可能丢失；自动化状态机发生静默回退。
- 当前状态：已确认；后续先读取 screen state，仅在明确存在 `INPUT_METHOD` 窗口时关闭 IME，并在每次导航后重新发现节点。
- 通用工具要求：Skill 不应把 `BACK` 当作通用键盘关闭命令；companion 的 `dismiss_keyboard` 修复后应成为唯一首选，并返回关闭前后窗口证据。

### TY-009：无关物理 ADB transport 使 Supervisor status 整体失败

- 复现：Windows ADB 同时存在物理 serial 和注册的本机 emulator；调用 `Invoke-AndroidLab.ps1 -Action status -DeviceId codex_api36`。
- 表现：旧 `Get-LabSerial` 在解析目标 AVD 前因检测到任意物理 transport 直接抛出拒绝错误，无法返回 codex emulator 的脱敏状态。
- 影响：物理设备未被操作，但会阻断无关 emulator 的只读状态检查和后续恢复诊断。
- 当前状态：已修复。`Test-LabAllowedSerial` 只允许 `emulator-*` 或注册目标 loopback serial；无关物理 serial 被忽略，物理 serial 仍不会被解析为目标。
- 验证：源码和 `0.1.2` 安装副本 `status -DeviceId codex_api36` 返回单行 JSON；status contract 覆盖 emulator、loopback 和物理 serial 边界。
- 安全边界：本批未连接、输入、点击、截图或读取物理设备；未放宽物理设备作为 MCP 目标的拒绝规则。

## 2026-08-22 Codex-ready 0.1.3 边界

- 已将本地项目明确记录为上游 `android-remote-control-mcp` `v1.11.1` 的派生开发；本地增强范围是 Windows/Codex Broker、stdio、Supervisor、lease/session、AVD 路由和 Skill。
- canonical Skill、Codex bootstrap 和分发声明已进入 0.1.3；0.1.2 仍是冻结回滚基线。
- 0.1.3 静态与包级验证通过，但未进行 Codex 重启后的真实 MCP 回归。第二台 Windows 和跨电脑验收仍 pending。
- companion native `type_clear_text`/`dismiss_keyboard` 源码仍不可用；现有 postcondition 门禁不能替代 native 修复。

## 已验证的设计约束

- 模拟器 UI、输入、截图、应用启动和安装后的交互只经 `android_lab`。
- Skill 不读取、复制、输入或持久化 API Key；凭据输入必须由用户本人完成。
- lease 在完整工作流内保持，成功、失败或取消后释放；释放 lease 不应关闭 AVD。
- `arm64` PRoot 在当前 x86_64 Windows 上的 `SIGABRT (-134)` 是运行环境阻塞，不通过修改 ABI、删除 PRoot 或伪造结果处理。
