# 2026-08-22 Android MCP root source migration

根目录 `android-mcp-lab/` 已成为活动源码入口；`development/android-mcp-lab/` 保留为迁移前冻结回滚快照。迁移包含 160 个文件，逐文件 SHA-256 与快照一致；历史 `node_modules` junction 继续指向工作区外的依赖目录。全局 MCP 仍使用 AppData `install\0.1.2` 运行时，未初始化 Git、未重打包 ZIP、未操作 AVD。

完整迁移记录见根目录 [`changes/2026-08-22-android-mcp-root-source-migration.md`](../../changes/2026-08-22-android-mcp-root-source-migration.md)。
