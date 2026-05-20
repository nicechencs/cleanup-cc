# Claude Code 缓存清理工具

Windows 平台的 Claude Code 缓存清理脚本，用于清理旧的会话数据和临时文件，释放磁盘空间。

## 文件说明

- `cleanup-sessions.ps1` - PowerShell 主脚本（UTF-8 with BOM 编码）
- `cleanup-sessions.bat` - 批处理启动器（UTF-8 with BOM 编码）
- `cleanup-sessions.txt` - 原始 Bash 脚本（参考用）

## 使用方法

### 方式一：双击运行（推荐）

直接双击 `cleanup-sessions.bat` 文件，按照提示操作：

1. 选择清理时间范围（7/14/30/60/90 天或自定义）
2. 选择执行模式（干运行预览 或 实际删除）
3. 选择是否清理用户配置和认证文件（可选）
   - .claude.json（用户配置、User ID、统计）
   - .credentials.json（认证凭据，删除后需重新登录）
4. 查看清理结果

### 方式二：命令行运行

```cmd
cleanup-sessions.bat
```

### 方式三：直接运行 PowerShell 脚本

```powershell
.\cleanup-sessions.ps1
```

## 清理内容

脚本会清理以下内容：

### 项目会话数据
- `~\.claude\projects\*\*.jsonl` - 会话日志文件
- `~\.claude\projects\*\<UUID>` - 会话目录（保留 memory 目录）

### 临时数据
- `~\.claude\debug\` - 调试文件
- `~\.claude\shell-snapshots\` - Shell 快照
- `~\.claude\file-history\` - 文件历史
- `~\.claude\todos\` - 待办事项
- `~\.claude\plans\` - 计划文件
- `~\.claude\tasks\` - 任务文件
- `~\.claude\paste-cache\` - 粘贴缓存
- `~\.claude\image-cache\` - 图片缓存
- `~\.claude\cache\` - 通用缓存
- `~\.claude\telemetry\` - 遥测数据
- `~\.claude\statsig\` - Statsig 缓存（A/B 测试和功能标志）
- `~\.claude\downloads\` - 下载文件
- `~\.claude\session-env\` - 会话环境配置

### 配置和状态文件
- `~\.claude\security_warnings_state_*.json` - 安全警告状态
- `~\.claude\history.jsonl` - 命令历史记录
- `~\.claude\stats-cache.json` - 使用统计缓存
- `~\.claude\mcp-needs-auth-cache.json` - MCP 认证缓存
- `~\.claude\backups\.claude.json.backup.*` - 配置文件备份

### 空目录清理
- 自动清理所有上述目录中的空子目录
- 包括项目目录下的空 UUID 会话目录

### 特殊清理项（需用户确认）
- `~\.claude\.claude.json` - 用户配置（包含 User ID、使用统计、提示历史等，可选清理）
- `~\.claude\.credentials.json` - 认证凭据（可选清理，删除后需重新登录）

## 安全特性

- **干运行模式**：默认仅预览，不删除文件
- **交互式确认**：执行删除前需要二次确认
- **保护重要数据**：不会删除 memory 目录和核心配置文件
- **认证凭据保护**：默认不清理，需用户明确选择
- **详细统计**：显示将要删除的文件数量和大小

## 编码说明

**重要**：为确保中文正确显示，文件必须使用正确的编码格式：

- `cleanup-sessions.ps1` - **UTF-8 with BOM**
- `cleanup-sessions.bat` - **UTF-8 with BOM**

如果中文显示乱码，请使用支持编码转换的编辑器（如 VS Code、Notepad++）将文件转换为 UTF-8 with BOM 编码。

### 在 VS Code 中设置编码

1. 打开文件
2. 点击右下角的编码显示（如 "UTF-8"）
3. 选择 "Save with Encoding"
4. 选择 "UTF-8 with BOM"

## 示例输出

```
========================================
  Claude Code 缓存清理工具
========================================

请选择要清理的文件时间范围：
  [1] 7 天前的文件（推荐）
  [2] 14 天前的文件
  [3] 30 天前的文件
  [4] 60 天前的文件
  [5] 90 天前的文件
  [6] 自定义天数
  [7] 清理所有文件（不限天数）

请输入选项 (1-7): 1

已选择：清理超过 7 天的文件

请选择执行模式：
  [1] 干运行模式（仅预览，不删除文件）- 推荐先预览
  [2] 执行模式（实际删除文件）

请输入选项 (1-2): 1

是否清理用户配置和认证文件？

  [1] .claude.json - 用户配置（包含 User ID、使用统计等）
      删除后会重置使用统计和提示历史

  [2] .credentials.json - 认证凭据
      删除后需要重新登录 Claude Code

  [3] 两者都清理
  [4] 都不清理（推荐）

请输入选项 (1-4): 4

已选择：保留所有配置和认证文件

========================================
=== 干运行模式（仅预览，不会删除文件） ===
清理目标：超过 7 天的文件

[项目/会话日志]
  my-project: 15 个文件, 3 个目录 (125.5 MB)

[其他临时数据]
  调试/: 8 个文件 (2.3 MB)
  shell快照/: 12 个文件 (1.1 MB)

========================================
  清理摘要
========================================
文件数量: 35
目录数量: 3 (UUID会话目录)
节省空间: 128.9 MB

这是预览结果，文件尚未删除。
如需实际删除，请重新运行脚本并选择执行模式。
```

## 注意事项

1. **建议先预览**：首次使用建议选择干运行模式，确认要删除的内容
2. **不可恢复**：执行删除后无法恢复，请谨慎操作
3. **定期清理**：建议每月运行一次，保持磁盘空间充足
4. **保留天数**：根据实际需求选择，一般 7-30 天即可
5. **清理所有**：选项 7 会清理所有符合条件的文件，不限天数，请谨慎使用

## 故障排除

### 中文乱码
- 确保文件编码为 UTF-8 with BOM
- 在 PowerShell 中运行：`chcp 65001`

### 权限错误
- 以管理员身份运行
- 确保有 .claude 目录的读写权限

### 脚本无法执行
- 检查 PowerShell 执行策略
- 使用 BAT 文件启动（会自动绕过策略）

## 版本历史

- v2.0 - 添加交互式界面，改进中文支持
- v1.0 - 初始版本
