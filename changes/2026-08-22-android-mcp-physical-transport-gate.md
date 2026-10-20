# 2026-08-22 Android MCP physical transport gate

阶段：MC6-Skill-vNext
状态：源码与 0.1.2 安装副本已修复，真实 Codex smoke 待 DSH Mobile 任务释放
范围：Global Lab Supervisor / ADB transport 解析 / status contract

## 目标

允许无关的物理 ADB transport 保持连接时继续检查和控制注册的本机 emulator，同时保证任何物理 serial 都不会成为 Android MCP 操作目标。

## 诊断

- ADB server 正常监听 `127.0.0.1:5037`，Broker health 为 `ready`。
- ADB 同时出现一个非 emulator transport 和一个 emulator transport；原 `Get-LabSerial` 因物理设备存在而让 `status` 整体失败。
- `codex_api36` 当前没有运行中的 emulator 进程，AVD lock PID 已失效；安装副本 status 返回 `offline`，并保留脱敏的 ADB transport 未注册失败。

## 改动

- `Common.ps1` 新增 `Test-LabAllowedSerial`，只允许 `emulator-*` 或目标 AVD 预期的 loopback serial。
- `Get-LabSerial` 不再因无关物理 transport 的存在而提前失败；物理 serial 仍不会进入候选解析集合。
- `tests/status-contract.ps1` 新增 emulator、loopback 和物理 serial 边界断言。
- 使用 `Sync-AndroidMcpLabInstall.ps1` 同步到 `%LOCALAPPDATA%\WhiteCodex\AndroidMcpLab\install\0.1.2`。

## 验证

- TypeScript strict typecheck：通过。
- PowerShell AST parse：通过。
- vNext contract：通过。
- status contract：通过。
- Config acceptance：通过。
- 安装副本 `status -DeviceId codex_api36`：返回单行 JSON，不再因物理 transport 失败；当前状态为 `offline`，`adbRegistered=false`。
- 源码与安装副本关键文件 SHA-256：一致。
- `0.1.2` ZIP SHA-256：保持 `882739f19f5701ca906e0f89153f6689758d431a573788e369168926697d5593`。
- 敏感 token-pattern scan：0 个匹配文件。
- lease 目录：为空。

## 未验证风险

- DSH Mobile Codex 任务仍为 active，未重启 Codex，未执行 `codex_api36` acquire/start/screen/release 真实 smoke。
- `codex_api36` 的 guest boot/ADB transport 问题仍未解决；若重启后再次出现 guest boot 无 ADB，必须记录 `ENV_BLOCKED / adb_unavailable`。
- companion native `type_clear_text` 与 `dismiss_keyboard` 源码不可得，本批未修改。
- 第二台 Windows、自然语言 Skill 隐式触发和真实取消/进程退出回归仍未完成。

## 安全与回退

- 未读取、输入或保存 API Key、OAuth、Authorization、DPAPI 或私有会话正文。
- 未执行 direct ADB 点击、输入或截图；未连接或操作物理设备。
- 未修改外部业务项目、AVD ABI、系统镜像或 PRoot。
- 回退方式：恢复 `Common.ps1` 与安装副本的上一版，并重新运行静态门禁；ZIP 不受本批影响。

## 下一准确断点

等待 DSH Mobile 任务释放 Codex/MCP 后，重启 Codex；仅使用无凭据 `codex_api36` 执行 devices → acquire → status →（非 ready 时）start → screen state → release，并同步最终脱敏结果。
