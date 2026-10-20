# Android MCP Global Lab Timeout Diagnosis

日期：2026-08-21

## 结论

本机旧窗口的主要 Timeout 来源是 `codex_api36` 冷启动阶段，不是 Broker 端口不可达，也不是普通 Android UI 调用超时。当前安装副本没有从全局 MCP 配置继承有效的 `ANDROID_SDK_ROOT`，错误地选中了缺少 API 36 system image 的 `%LOCALAPPDATA%\Android\Sdk`；Emulator 因而立即报 `Cannot find AVD system path`，但旧监督脚本仍等待完整的 240 秒。AVD 同时遗留了指向不存在进程的 `hardware-qemu.ini.lock\pid`（PID 20556），通过 MCP 的 `android_lab_start` 在约 204 秒时先收到 `-32001 Request timed out`。

另有一个独立的会话生命周期现象：Broker 重启会使旧 `launcher.mjs`/`proxy.mjs` 进程持有的 Streamable HTTP session 失效，旧代理随后返回 `Invalid or missing MCP session`。Broker 本身仍健康，fresh launcher 的 `devices`、`tools/list`、`acquire` 和 `status` 均可快速完成；这类代理应在 Codex 重启后重新建立，不应作为 Android companion 挂死来判断。

## 证据

- `Invoke-AndroidLab.ps1 -Action status`：Broker 运行时与注册表均可读，6 台设备可枚举；`codex_api36` 初始为 `offline`。
- `Invoke-AndroidLab.ps1 -Action doctor`：`adb`、`emulator`、注册表和固定 companion APK 均通过。
- `http://127.0.0.1:18190/health`：Broker 返回 `status=ready`，监听端口为本机 loopback。
- fresh stdio bridge：63 个工具、`android_lab_devices`、`android_lab_acquire`、`android_lab_status` 和 lease release 均在毫秒级完成。
- `android_lab_start(codex_api36)`：等待约 204 秒后返回 MCP `-32001 Request timed out`；随后 AVD 进程不存在，设备仍为 `offline`。
- 捕获到的 Emulator 日志：没有 SDK 环境时为 `FATAL Cannot find AVD system path`；传入 `%ANDROID_SDK_ROOT%` 后能找到 system image，并报告约 31 秒 Android boot complete。
- 传入有效 SDK 且执行一次受控 `-wipe-data` 后，Emulator 仍未在 ADB server 注册 `emulator-5564`；`adb devices` 为空、端口 5564 不监听，`adb connect 127.0.0.1:5564` 被拒绝。该 ADB/AVD 现场阻塞尚未继续扩大修复。
- 直接运行官方 `Invoke-AndroidLab.ps1 -Action up -DeviceId codex_api36 -Headless`：无 SDK 环境时等待 240 秒后报 boot timeout；有效 SDK 环境下已能完成 guest boot，但仍因 ADB 不可见而等待超时。
- `%USERPROFILE%\.android\avd\codex_api36.avd\hardware-qemu.ini.lock\pid` 内容为 `20556`，对应进程不存在；`multiinstance.lock` 同样遗留。

## 判断

- **不是 Broker 超时**：Broker health/status 和 fresh stdio MCP 握手均快速通过，端口 `18190` 正常监听。
- **不是普通 Android MCP screen 调用超时**：screen 请求尚未进入可用 companion；冷启动的 `runtime` 监督路径先受 SDK 根目录配置影响，修正后又受 ADB 注册阻塞。
- **不是当前 Codex 任务窗口单独的上下文耗尽**：在同一主机 fresh stdio bridge 中可复现，且官方脚本也独立等待 240 秒后失败。
- **会话失效是次要生命周期问题**：旧代理跨 Broker 重启后携带过期 MCP session，需重启 Codex/相关 MCP 进程重建；本批次不改 0.1.2 协议或离线包版本。

本机收尾时已终止残留的 0.1.2 launcher/proxy 子进程并停止 Broker；下一次 Codex MCP 启动会从安装副本重新握手，不会复用本次旧 session。

## 修复范围

已落盘的最小修复：

- `Common.ps1` 在启动 AVD 前只清理由不存在进程持有的 `hardware-qemu.ini.lock` 和 `multiinstance.lock`；活动进程的锁保持不动。
- 启动 Emulator 时显式继承脚本选择的 `ANDROID_SDK_ROOT`/`ANDROID_HOME`，并在子进程提前退出时立即报错，不再假装等待 240 秒。
- 全局 `android_lab` 配置补充当前主机有效 SDK 根目录，并把 `startup_timeout_sec` / `tool_timeout_sec` 对齐为 300 秒。
- 不触碰 `dsh_api36`、凭据或离线 ZIP；当前 ZIP SHA-256 保持 `882739f19f5701ca906e0f89153f6689758d431a573788e369168926697d5593`。

## 未验证风险

- 本机 `codex_api36` 已能完成 Android guest boot，但 ADB 注册仍失败；MCP screen/companion 回归因此阻塞，需后续单独处理 ADB/AVD 现场。
- 第二台 Windows、Codex 重启后的 Skill 隐式触发、跨任务并行演示仍未验证。
- 旧 Broker 代理的自动重连未在本批次实现；当前恢复动作是重启 Codex，使 stdio launcher 重新握手。当前任务内直接调用仍返回 `Invalid or missing MCP session`，属于旧 stdio session 已失效。

## 凭据与安全

本诊断未读取、输出或输入 API Key、OAuth、Authorization、DPAPI 明文或用户会话正文；仅使用无凭据 `codex_api36`，并通过 MCP 完成租约清理。
