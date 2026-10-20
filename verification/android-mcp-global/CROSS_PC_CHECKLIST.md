# 第二台 Windows 验收清单

在另一台电脑完成以下步骤后，才能把 `crossComputerAcceptance` 改为 `passed`：

1. 校验 `Android-Mcp-Lab-0.1.0.sha256`。
2. 解压 ZIP，执行 `Install-AndroidMcpLab.ps1 -OfflineBundle . -RegisterGlobalConfig`。
3. 确认 `android_lab_devices` 只列本机 AVD，不出现第一台电脑的 Token、会话或路径。
4. 启动一个 API 33+ x86_64 测试 AVD，验证列表、点击、输入、返回、应用切换、截图和日志。
5. 验证同一设备租约冲突；再验证两个不同 AVD 可并行。
6. 确认 `dsh_api36` 的保护策略显示 `contains-credentials/preserve`，不清数据。
7. 卸载并确认 AVD、Android SDK 和项目目录仍在。

本清单不要求连接真机，也不要求输入任何模型或图片 API Key。
