# Android MCP Global Lab v1.1 验收结果

日期：2026-08-20

## 0.1.2 packaging refresh（本机）

- `android_lab_status` 单行 JSON 修复已正式纳入 `Android-Mcp-Lab-0.1.2.zip`；包 SHA-256 为 `882739f19f5701ca906e0f89153f6689758d431a573788e369168926697d5593`。
- 源码 strict typecheck、隔离安装到 `%LOCALAPPDATA%\WhiteCodex\AndroidMcpLab\install\0.1.2`、`Invoke-AndroidLab.ps1 -Action status` 单行且可解析、包内敏感值模式扫描均通过。
- 新包 acceptance：63 工具、`codex_api36`、Settings 打开、屏幕读取、截图、Back、同设备 lease 冲突、无凭据并行 lease 和释放通过；无真实模型、图片或 OAuth 请求。
- 本机 `$ty-android-mcp 读取 codex_api36 当前屏幕` 工作流通过：Skill UTF-8 静态校验、设备发现、租约、Settings 屏幕读取和释放通过；Skill 自动隐式触发仍需 Codex 重启后的新任务确认。
- `Invoke-AndroidLabAcceptance.ps1 -Mode Config`（0.1.2 安装副本）：通过，确认全局 `android_lab` 已指向 0.1.2、`approval_policy=never`、`sandbox_mode=danger-full-access` 且无 token-like 配置值。
- `Invoke-AndroidLabAcceptance.ps1 -Mode Full -DeviceId codex_api36`（0.1.2 安装副本）：MCP route 及所有设备/隔离/配置检查通过；bootstrap 单项因该主机新安装副本找不到 `sdkmanager` 而 blocked。已有 SDK 主机工具与 AVD 可用，故这不是 0.1.2 路由回归；跨电脑安装仍需 Android SDK Command-line Tools 前置。

## 已通过

- TypeScript strict typecheck：通过。
- 固定 APK 供应链：SHA-256 `39fbe125840ebd68eb8c6af7c509f1e8e65ed61f0890f841e29bf83830f3c581`，证书摘要 `2c44a5870e8a222bf790d45843fd57391e01f28212adea8c50ccce2d68dc2d4b`。
- 本机 AVD 自动发现：`dsh_api36`、`dsh_api26`、`dsh_api36_test`、`openminis_api36`、`openminis_api36_arm64`。
- API 26 与 arm64 AVD 自动登记但被 MCP 能力门禁禁用；不会尝试安装 API 33+ companion APK。
- Broker 只监听 `127.0.0.1:18190`，MCP 需要 DPAPI 解密后的本机 Bearer。
- 全局工具列表：63 个，包含 57 个上游工具和 6 个管理工具。
- `openminis_api36` 通过全局桥实际读取屏幕状态。
- 同设备租约冲突、过期租约回收、无租约写操作、未知设备拒绝：通过。
- 兼容前缀代理：57 个旧式工具名和实际屏幕调用通过。
- 历史 `0.1.1` 离线包曾安装到 `%LOCALAPPDATA%\WhiteCodex\AndroidMcpLab\install\0.1.1`；本轮 `0.1.2` 隔离安装到 `%LOCALAPPDATA%\WhiteCodex\AndroidMcpLab\install\0.1.2`，两者安装目录列表 smoke 均通过。
- 全局 Codex 配置追加 `android_lab`，原配置先备份。

本轮复核（2026-08-20）：

- `bridge-smoke.mjs`：63 个通用工具、`openminis_api36` 屏幕读取和 acquire/release 通过。
- `lease-smoke.mjs`：同设备冲突、过期租约回收、无 lease 写操作和未知设备拒绝通过。
- `legacy-smoke.mjs`：57 个 `android_dsh36_*` 工具、旧 schema 参数裁剪和 `dsh_api36` 只读屏幕调用通过。
- 明确停止 Broker 后从安装目录冷启动：63 工具、Settings 打开、截图、返回、同设备冲突、并行 lease 和释放均通过。
- `Invoke-AndroidLabAcceptance.ps1 -Mode Full -DeviceId codex_api36`：通过，结果见 `%LOCALAPPDATA%\WhiteCodex\AndroidMcpLab\logs\acceptance-20260820-050821.json`。
- 历史 `0.1.1` 包 SHA-256 为 `4576a44a6db48dbdc6675217546d97a2d3cfd6e5d225649c973b7b2e63ff4f51`；当前 `0.1.2` 包 SHA-256 为 `882739f19f5701ca906e0f89153f6689758d431a573788e369168926697d5593`。

对应脱敏 JSON 保存在 `verification/android-mcp-global/bootstrap/`。

## 重要阻塞与处理

- 第一次尝试按需启动 `dsh_api26` 时，安装器收到 `INSTALL_FAILED_OLDER_SDK`。这确认了固定 MCP APK 的最低 API 约束，随后已加入注册表 API 级别门禁；该 AVD 已停止并恢复为离线状态。
- 安装目录 Broker 首次真实路由曾因 companion service 刚重启导致 `fetch failed`；连接层已加入指数等待，fresh foreground route 随后通过并返回真实屏幕内容。
- Windows Node 在一个“父进程立即 `client.close()`、子进程同时退出”的内联关闭试验中打印过 libuv assertion，但进程退出码为 0；正常 `bridge-smoke`、lease smoke 和实际路由不受影响。该关闭噪声仍列为下一批生命周期清理项，不宣称已完全消除。

## 未完成外部门槛

- 第二台 Windows 电脑尚未实际解压、安装和运行离线包；本机通过不等于跨电脑通过。
- 尚未把新的全局工具在 Codex 重启后的真实 UI 任务中做跨任务并行演示。
- Windows Node 在立即关闭子进程的特殊内联测试中有一次 libuv assertion 噪声，正常冷启动、generic、lease 和 legacy smoke 未复现；stdio lifecycle 清理仍可作为后续小批次。

## 凭据与数据

本批次没有读取、打印或传输 DSH 文本 Key、图片 Key、OAuth token、DPAPI 明文或用户会话正文；`dsh_api36` 只执行兼容桥的只读屏幕调用，未运行清数据、卸载或 instrumentation。`openminis_api36` 和 `codex_api36` 只用于无凭据控制 smoke。

## 2026-08-21 Timeout 诊断批次

- 旧窗口 Timeout 已定位到本机 `codex_api36` 冷启动链：安装副本未继承有效 SDK 根目录，且遗留失效 AVD 锁导致监督脚本等待到上限；不是 Broker health/端口故障。
- `Common.ps1` 源码与当前 0.1.2 安装副本已同步 stale-lock 清理、SDK 环境继承和提前退出报错；全局 `android_lab` 配置补充 `%ANDROID_SDK_ROOT%`，启动/工具截止时间为 300 秒。
- fresh stdio 63 工具、`codex_api36` devices/acquire/status/release 通过，lease 目录为空；strict typecheck 与 Config acceptance 通过。
- 有效 SDK 下 Emulator 可报告约 31 秒 guest boot，但 `emulator-5564` 仍未注册到 ADB server，screen/companion 回归未通过；一次受控 `codex_api36 -wipe-data` 未改变该现场，因此 MC6 仍为部分完成。
- 当前 Codex 旧 MCP stdio session 仍返回 `Invalid or missing MCP session`，需重启 Codex 后重新握手；0.1.2 ZIP SHA-256 保持 `882739f19f5701ca906e0f89153f6689758d431a573788e369168926697d5593`。
- 详细诊断：`verification/android-mcp-global/timeout-diagnosis.md`；批次记录：`changes/2026-08-21-android-mcp-timeout-diagnosis.md`。

## 2026-08-22 TY Android MCP vNext 第一批

- Skill/Global Lab 源码和当前用户安装副本已同步 fresh-state、输入复核、IME 门禁、结构化 startup status、`adb_unavailable`、`catalog_mismatch`、只读 session recovery 和通用 lease cleanup。
- `tsc --noEmit -p tsconfig.json`、PowerShell AST parse、`node --import tsx/esm tests/vnext-contract.mjs`、`tests/status-contract.ps1` 和 Config acceptance 通过。
- 该批次不是完整运行时通过：活动 Codex MCP session 尚未重启；第二台 Windows、隐式 Skill 触发、真实取消/stdio close 和 ADB transport 回归仍待完成。
- TY-005/TY-006 的 companion native 实现未改动，因为 companion 源码不在 Global Lab；桥接层和 Skill 已将字段复核、fresh screen state、IME presence/absence 和分类错误设为硬门槛。
- 详细批次记录：`changes/2026-08-22-ty-android-mcp-vnext.md`；根目录交接：`../../../../changes/2026-08-22-ty-android-mcp-vnext-root-record.md`。

## 2026-08-22 交接前静态复核

- 源码与 `0.1.2` 安装副本的关键入口 SHA-256 一致；typecheck、PowerShell AST、vNext/status contract、Config acceptance、JSON 解析和敏感扫描通过。
- lease 目录为空；没有启动/停止模拟器、重启 Codex、调用 direct ADB 或请求真实模型/图片/OAuth。
- 发现多个 Codex 管理的 `0.1.2` Broker/proxy 进程，因此真实 `codex_api36` screen smoke 保持 pending，不能把本批升级为 `RUNTIME_PASS`。
- 详细记录：`changes/2026-08-22-android-mcp-handoff-static-recheck.md`。

## 2026-08-22 physical transport gate 修复

- 诊断确认 ADB 中存在一个非 emulator transport；旧 `Get-LabSerial` 会让整个 Supervisor status 直接失败。
- `Common.ps1` 新增 emulator/loopback serial 白名单解析；无关物理 transport 不再阻断注册 emulator 的 status/启动解析，任何物理 serial 仍不会成为目标。
- `tests/status-contract.ps1` 已覆盖 `emulator-*`、目标 loopback 和物理 serial 拒绝边界。
- 源码与 `%LOCALAPPDATA%\WhiteCodex\AndroidMcpLab\install\0.1.2` 已同步；安装副本 `status -DeviceId codex_api36` 返回单行 JSON，当前为 `offline`、`adbRegistered=false`，并保留脱敏的 ADB transport 未注册失败。
- TypeScript、PowerShell AST、vNext/status contract、Config acceptance、JSON 解析、敏感扫描、关键哈希和 lease 为空均通过；`0.1.2` ZIP SHA-256 未变。
- DSH Mobile 线程仍 active，本批未重启 Codex、未停止 Broker、未操作 AVD；真实 `codex_api36` acquire/start/screen/release 继续 pending。
- 详细记录：`changes/2026-08-22-android-mcp-physical-transport-gate.md`。

## 2026-08-22 根目录源码迁移

- 完整 MCP 源码已复制到活动入口 `android-mcp-lab/`；`development/android-mcp-lab/` 保留为冻结回滚快照。
- 迁移前后 160 个文件逐文件 SHA-256 一致；历史 `node_modules` junction 指向工作区外的依赖目录（不纳入公开树）。
- 根目录副本 typecheck、PowerShell AST、vNext/status contract、Config acceptance、JSON 和敏感扫描通过。
- 根目录脚本只读 status 当前返回 `codex_api36=ready`（`bootCompleted=true`、`adbRegistered=true`、`companionReady=true`）。未获取 lease、未读取屏幕、未调用 `android_lab_stop`。
- 收尾检查发现两个外部并行 lease（`codex_api36` / `codex-dsh-mobile-ui-smoke`，`dsh_api36_test` / `codex-dsh-mobile-instrumentation`）；本批未触碰或清理。
- 全局 MCP 仍使用 AppData `install\0.1.2`；根目录源码已同步安装副本；ZIP SHA-256 保持不变。

## 0.1.3 Codex-ready / upstream-derived Git（2026-08-22）

- `android-mcp-lab/` 已成为独立 Git repository；`main` + `v0.1.2` 保留已验证基线，当前开发分支为 `feature/codex-ready-0.1.3`，仅配置 `upstream` remote，未 push。
- 上游固定为 `android-remote-control-mcp` `v1.11.1`，tag commit `2b87d46e91421295cd4893185b694612ec2c94d1`；APK SHA-256 和证书 SHA-256 与既有 0.1.2 manifest 一致。
- canonical Skill 已纳入 `skill/ty-android-mcp/`；构建/安装新增 Codex bootstrap、Skill 安装备份、上游/许可证/安全/贡献声明。
- `npm run typecheck`、`npm run build`、PowerShell AST、vNext/status contract、Skill contract、0.1.3 包内容检查和离线 `-DiscoverOnly` 安装通过。
- 统一 `Invoke-CodexAndroidMcpBootstrap.ps1 -Mode Validate -RegisterGlobalConfig:$false` 通过；没有切换全局配置或启动 AVD。
- 0.1.3 ZIP SHA-256：`3b318449907599f0367040ee06707c6439000644b69285a15e6c69414aab96fb`。0.1.2 ZIP SHA-256 保持 `882739f19f5701ca906e0f89153f6689758d431a573788e369168926697d559`。
- 全局 Codex 仍指向 AppData `install/0.1.2`；本批不重启 Codex、不获取 lease、不启动/停止 AVD，故不宣称 `RUNTIME_PASS`。
- 未验证：Codex 重启后的 0.1.3 MCP smoke、第二台 Windows、真实进程取消/退出 lease cleanup、companion native TY-005/TY-006。
- DSH Mobile 线程仍 active，因此 Codex 重启后的完整 MCP smoke 和生命周期回归继续 pending。
- 详细记录：`changes/2026-08-22-android-mcp-root-source-migration.md`。

## 2026-08-22 根目录源码收口静态复核

- 从活动源码 `android-mcp-lab/` 运行 typecheck、PowerShell AST、vNext contract、status contract、Config acceptance、JSON 解析和敏感扫描，全部通过。
- 关键 TypeScript、编译产物、`Common.ps1` 和 contract 文件在根目录、`development/android-mcp-lab/` 快照与 AppData `install/0.1.2` 三方 SHA-256 一致。
- 根目录与 development 快照主体文件一致；差异仅为活动交接文档、迁移 dated record 和冻结快照 `MIGRATION_NOTICE.md`，不代表源码缺失。
- 根目录 `node_modules` junction 仍指向工作区外的依赖目录；全局 `android_lab` 配置仍指向 `%LOCALAPPDATA%\WhiteCodex\AndroidMcpLab\install/0.1.2`。
- `0.1.2` ZIP SHA-256 保持 `882739f19f5701ca906e0f89153f6689758d431a573788e369168926697d5593`。
- 当前 lease 目录存在一个外部 `codex_api36.json`；本批未创建、释放或修改，也未进行任何 AVD、Codex 重启、屏幕读取或 direct ADB UI 操作。
- 状态继续保持 `SOURCE_AND_INSTALL_VERIFIED`；Codex 重启后的真实 smoke、生命周期回归、第二台 Windows 和 companion native 输入实现仍 pending。
- 详细记录：`changes/2026-08-22-android-mcp-root-source-closeout.md`。
