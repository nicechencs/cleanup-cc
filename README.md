# Claude Code 缓存清理工具

跨平台的 Claude Code 缓存清理脚本，用于清理旧的会话数据和临时文件，释放磁盘空间。

支持平台：**Windows** / **macOS**

## 目录结构

```
cleanup-cc/
├── windows/
│   ├── cleanup-sessions.ps1     PowerShell 主脚本（UTF-8 with BOM）
│   └── cleanup-sessions.bat     批处理启动器（UTF-8 with BOM）
├── macos/
│   ├── cleanup-sessions.sh      Bash 主脚本（UTF-8，LF 行尾）
│   └── cleanup-sessions.command 双击启动器（UTF-8，LF 行尾）
└── README.md
```

两端脚本功能完全对齐（v3.0）：相同的预扫描、综合菜单、5 个清理级别、进程关闭、空目录清理与表驱动配置。

## 使用方法

### Windows

**方式一：双击运行（推荐）**

进入 `windows\` 目录，双击 `cleanup-sessions.bat`。

**方式二：命令行**

```cmd
cd windows
cleanup-sessions.bat
```

**方式三：直接运行 PowerShell**

```powershell
cd windows
.\cleanup-sessions.ps1
```

### macOS

**方式一：双击运行（推荐）**

进入 `macos/` 目录，双击 `cleanup-sessions.command`，会在 Terminal.app 中打开。

> 如果提示 "无法打开" 或 "权限不足"，先执行：
> ```bash
> chmod +x macos/cleanup-sessions.sh macos/cleanup-sessions.command
> ```
> 仓库内置 `.gitattributes` 已强制 LF 行尾，并通过 `git update-index --chmod=+x` 保留了可执行位，正常 clone 不需要再手动设置。

**方式二：命令行**

```bash
cd macos
./cleanup-sessions.sh
```

## 操作流程（v3.0 综合菜单）

启动后会先扫描可清理空间，然后通过一个综合菜单一次性选择清理级别：

```
当前可清理约 XXX MB（N 个文件，M 个会话目录）

请选择操作：
  [1] 预览（干运行，不删文件）                              - 推荐先跑一次
  [2] 执行清理（基础：会话/缓存/临时数据）
  [3] 执行清理 + 清理用户配置 .claude.json                  - 重置使用统计
  [4] 执行清理 + 清理认证 .credentials.json                 - 需重新登录
  [5] 执行清理 + 全清（配置 + 认证）                        - 等于重置登录状态
  [Q] 退出
```

选项 [3]/[4]/[5] 涉及破坏性操作（配置/认证），会再做一次二次确认。

执行模式下脚本会先尝试关闭正在运行的 Claude Code 桌面进程，避免文件占用。

## 清理内容

### 项目会话数据

- `~/.claude/projects/*/*.jsonl` — 会话日志文件
- `~/.claude/projects/*/<UUID>/` — UUID 格式的会话目录（保留 `memory` 目录）

### 临时数据（递归清理）

| 目录 | 用途 |
| --- | --- |
| `debug/` | 调试日志 |
| `shell-snapshots/` | Shell 快照 |
| `file-history/` | 文件历史 |
| `todos/` | 待办事项 |
| `plans/` | 计划文件 |
| `tasks/` | 任务文件 |
| `paste-cache/` | 粘贴缓存 |
| `image-cache/` | 图片缓存 |
| `cache/` | 通用缓存 |
| `telemetry/` | 遥测数据 |
| `statsig/` | Statsig 缓存（A/B 测试、功能标志） |
| `downloads/` | 下载文件 |
| `session-env/` | 会话环境配置 |

### 配置和状态文件

- `~/.claude/history.jsonl` — 命令历史
- `~/.claude/stats-cache.json` — 使用统计缓存
- `~/.claude/mcp-needs-auth-cache.json` — MCP 认证缓存
- `~/.claude/security_warnings_state_*.json` — 安全警告状态
- `~/.claude/backups/.claude.json.backup.*` — 配置文件备份

### 空目录清理

自动清理上述目录中产生的空子目录（包括项目目录下的空 UUID 会话目录）。

### 特殊清理项（菜单选项 3/4/5）

- `~/.claude/.claude.json` — 用户配置（User ID、使用统计、提示历史）
- `~/.claude/.credentials.json` — 认证凭据（删除后需重新登录）

## 安全特性

- **干运行预览**：菜单 [1] 仅统计可清理空间，不删除任何文件
- **预扫描**：启动时显示可清理总量，避免盲删
- **进程关闭**：执行清理前先关闭 Claude Code 桌面进程，防止文件占用
- **二次确认**：破坏性操作（清理配置/认证）需要单独确认
- **保留核心数据**：不会删除 `memory` 目录
- **容错继续**：单个文件删除失败时记录失败计数但不中断流程

## 编码与行尾

| 文件 | 编码 | 行尾 |
| --- | --- | --- |
| `cleanup-sessions.ps1` | UTF-8 with BOM | CRLF |
| `cleanup-sessions.bat` | UTF-8 with BOM | CRLF |
| `cleanup-sessions.sh` | UTF-8（无 BOM） | LF |
| `cleanup-sessions.command` | UTF-8（无 BOM） | LF |

仓库根目录的 `.gitattributes` 会自动锁定上述行尾，无需手动配置。

## 故障排除

### Windows：中文乱码

- 确认 `.ps1` / `.bat` 为 UTF-8 with BOM 编码
- 在 PowerShell 中执行 `chcp 65001` 切换控制台代码页

### Windows：脚本无法执行

- 通过 `.bat` 启动器运行（自动绕过 PowerShell 执行策略）
- 或单独以管理员身份打开 PowerShell 后运行

### macOS：`zsh: permission denied`

```bash
chmod +x macos/cleanup-sessions.sh macos/cleanup-sessions.command
```

### macOS：双击 `.command` 报 `bad interpreter: ^M`

文件被转成了 CRLF 行尾。修复：

```bash
sed -i '' $'s/\r$//' macos/cleanup-sessions.sh macos/cleanup-sessions.command
```

或重新 `git checkout` 这些文件（`.gitattributes` 会强制 LF）。

## 注意事项

1. **建议先预览**：首次使用请选 [1] 干运行预览
2. **不可恢复**：实际删除后无法恢复，请谨慎操作
3. **定期清理**：建议每月运行一次，长期使用 Claude Code 时会积累大量会话数据
4. **删除认证 = 重新登录**：选项 [4]/[5] 会清理 `.credentials.json`，下次启动需要重新登录

## 版本历史

- v3.0 — 综合菜单 + 预扫描 + 空目录清理 + 进程管理 + 表驱动；新增 macOS 版本
- v2.0 — 多步交互式菜单，改进中文支持
- v1.0 — 初始版本
