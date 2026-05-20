# 脚本清理项检查报告

## 检查时间
2026-04-02

## 当前脚本清理的内容

### ✅ 已包含的清理项

#### 项目会话数据
- [x] `~\.claude\projects\*\*.jsonl` - 会话日志文件
- [x] `~\.claude\projects\*\<UUID>\` - UUID 会话目录（保留 memory）

#### 临时数据目录
- [x] `~\.claude\debug\` - 调试文件
- [x] `~\.claude\shell-snapshots\` - Shell 快照（236KB, 39个文件）
- [x] `~\.claude\file-history\` - 文件历史
- [x] `~\.claude\todos\` - 待办事项
- [x] `~\.claude\plans\` - 计划文件
- [x] `~\.claude\tasks\` - 任务文件
- [x] `~\.claude\paste-cache\` - 粘贴缓存
- [x] `~\.claude\image-cache\` - 图片缓存
- [x] `~\.claude\cache\` - 通用缓存（新增）
- [x] `~\.claude\telemetry\` - 遥测数据（新增）

#### 配置和状态文件
- [x] `~\.claude\security_warnings_state_*.json` - 安全警告状态
- [x] `~\.claude\history.jsonl` - 命令历史（355KB）（新增）
- [x] `~\.claude\stats-cache.json` - 统计缓存（8.2KB）（新增）
- [x] `~\.claude\mcp-needs-auth-cache.json` - MCP 认证缓存（103B）（新增）
- [x] `~\.claude\backups\.claude.json.backup.*` - 配置备份（5个文件，~7.5KB）（新增）

### ❌ 不应清理的文件（受保护）

- ❌ `~\.claude\settings.json` - 主配置文件（包含 API 密钥）
- ❌ `~\.claude\settings.local.json` - 本地配置覆盖
- ❌ `~\.claude\CLAUDE.md` - 用户全局指令
- ❌ `~\.claude\projects\*\memory\` - 项目记忆目录

### ⚠️ 需用户确认的文件（默认不清理）

- ⚠️ `~\.claude\.claude.json` - 用户配置（User ID、使用统计、提示历史）
- ⚠️ `~\.claude\.credentials.json` - 认证凭据（删除后需重新登录）

### 📊 新增清理项统计

本次更新新增了 **9 个清理项**：

**自动清理（基于时间）：**
1. **history.jsonl** (355KB) - 命令历史记录
2. **stats-cache.json** (8.2KB) - 使用统计缓存
3. **mcp-needs-auth-cache.json** (103B) - MCP 认证缓存
4. **cache/** 目录 - 通用缓存
5. **backups/** 目录 - 配置文件备份（5个文件）
6. **telemetry/** 目录 - 遥测数据

**需用户确认（不受时间限制）：**
7. **.claude.json** - 用户配置文件（User ID、统计、提示历史）
8. **.credentials.json** - 认证凭据文件

预计额外可清理空间：**~365KB+**（仅计算已知文件）

## 清理逻辑说明

### 时间判断
所有文件和目录都基于 `LastWriteTime`（最后修改时间）判断：
- 只清理超过指定天数（默认7天）的文件
- 使用 `-lt $cutoffDate` 比较

### 安全机制
1. **干运行模式**：默认启用，仅预览不删除
2. **二次确认**：执行模式需要用户输入 Y 确认
3. **保护目录**：memory 目录被明确排除
4. **错误处理**：使用 `-ErrorAction SilentlyContinue` 避免因文件不存在而报错

## 目录大小参考（当前系统）

```
~\.claude\shell-snapshots\    236KB (39 文件)
~\.claude\history.jsonl       355KB
~\.claude\stats-cache.json    8.2KB
~\.claude\backups\            24KB (5 文件)
```

## 建议

### 清理频率
- **日常使用**：每周运行一次，保留 7 天
- **重度使用**：每 3-5 天运行一次
- **轻度使用**：每月运行一次，保留 30 天

### 保留天数建议
- **7 天**：适合日常使用，保持系统清洁
- **14 天**：适合需要回溯最近工作的场景
- **30 天**：适合轻度使用或需要长期历史记录

### 特殊情况
- **重要项目进行中**：建议保留 14-30 天
- **磁盘空间紧张**：可以设置为 3-5 天
- **首次清理**：建议先用 30 天测试，确认无误后再缩短

## 更新日志

### v2.2 (2026-04-02)
- ✅ 新增 .claude.json 清理选项（需用户确认）
- ✅ 改进用户配置清理界面，合并认证和配置选项
- ✅ 更新文档说明

### v2.1 (2026-04-02)
- ✅ 新增 history.jsonl 清理
- ✅ 新增 stats-cache.json 清理
- ✅ 新增 mcp-needs-auth-cache.json 清理
- ✅ 新增 cache/ 目录清理
- ✅ 新增 backups/ 目录清理
- ✅ 新增 telemetry/ 目录清理
- ✅ 新增 .credentials.json 清理选项（需用户确认）
- ✅ 更新 README.md 文档

### v2.0 (2026-04-02)
- 初始版本，包含基本清理功能
