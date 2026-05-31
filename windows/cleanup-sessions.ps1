<#
.SYNOPSIS
    Claude Code 缓存清理工具 (Windows PowerShell 版本)

.DESCRIPTION
    自动清理 Claude Code 产生的会话数据和临时文件，释放磁盘空间。
    启动时预扫描显示可清理空间，通过单一综合菜单一次选择清理范围。

.NOTES
    文件编码：UTF-8 with BOM
    作者：Claude Code
    版本：3.0
#>

# 遇到错误时停止执行（删除循环内改为 try/catch 单独处理）
$ErrorActionPreference = "Stop"

# 设置控制台输出编码为 UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Claude Code 数据目录路径
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$ProjectsDir = Join-Path $ClaudeDir "projects"

# 递归清理目标：ClaudeDir 下会递归扫描删除的子目录
$CleanTargets = @(
    @{Dir="debug"; Label="调试"},
    @{Dir="shell-snapshots"; Label="shell快照"},
    @{Dir="file-history"; Label="文件历史"},
    @{Dir="todos"; Label="待办事项"},
    @{Dir="plans"; Label="计划"},
    @{Dir="tasks"; Label="任务"},
    @{Dir="paste-cache"; Label="粘贴缓存"},
    @{Dir="image-cache"; Label="图片缓存"},
    @{Dir="cache"; Label="通用缓存"},
    @{Dir="telemetry"; Label="遥测数据"},
    @{Dir="statsig"; Label="Statsig缓存"},
    @{Dir="downloads"; Label="下载"},
    @{Dir="session-env"; Label="会话环境"}
)

# ClaudeDir 根目录下会单独删除的独立文件
$SingleFiles = @(
    @{Name="history.jsonl"; Label="命令历史"},
    @{Name="stats-cache.json"; Label="统计缓存"},
    @{Name="mcp-needs-auth-cache.json"; Label="MCP认证缓存"}
)

# 删除失败计数（脚本作用域，供函数内 try/catch 累加）
$script:failCount = 0

<#
.SYNOPSIS
    将字节数格式化为人类可读的大小格式
#>
function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) {
        return "{0:N1} GB" -f ($Bytes / 1GB)
    } elseif ($Bytes -ge 1MB) {
        return "{0:N1} MB" -f ($Bytes / 1MB)
    } elseif ($Bytes -ge 1KB) {
        return "{0:N1} KB" -f ($Bytes / 1KB)
    } else {
        return "{0} B" -f $Bytes
    }
}

<#
.SYNOPSIS
    关闭正在运行的 Claude Code 相关进程
#>
function Stop-ClaudeCodeProcesses {
    $processes = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'Claude.exe'" -ErrorAction SilentlyContinue |
                   Sort-Object -Property ProcessId -Unique)

    Write-Host "[进程处理]"

    if ($processes.Count -eq 0) {
        Write-Host "  未发现正在运行的 Claude Code 进程" -ForegroundColor Gray
        Write-Host ""
        return @{Stopped=0; Remaining=0}
    }

    $processIds = @($processes | ForEach-Object { $_.ProcessId })
    Write-Host "  发现 $($processes.Count) 个 Claude Code 进程 (PID: $($processIds -join ', '))" -ForegroundColor Yellow
    Write-Host "  正在关闭 Claude Code 相关进程..." -ForegroundColor Yellow

    foreach ($process in $processes) {
        try {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
        } catch {
            Write-Host "  无法结束 PID $($process.ProcessId): $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Start-Sleep -Milliseconds 800

    $remaining = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'Claude.exe'" -ErrorAction SilentlyContinue |
                   Where-Object { $processIds -contains $_.ProcessId })
    $stoppedCount = $processes.Count - $remaining.Count

    if ($stoppedCount -gt 0) {
        Write-Host "  已结束 $stoppedCount 个 Claude Code 进程" -ForegroundColor Green
    }

    if ($remaining.Count -gt 0) {
        Write-Host "  仍有 $($remaining.Count) 个 Claude Code 进程未退出 (PID: $((@($remaining | ForEach-Object { $_.ProcessId })) -join ', '))" -ForegroundColor Red
    }

    Write-Host ""
    return @{Stopped=$stoppedCount; Remaining=$remaining.Count}
}

<#
.SYNOPSIS
    预扫描所有清理目标，返回合计大小/文件数/会话目录数，用于菜单前的提示
#>
function Get-CleanupPreview {
    $bytes = 0
    $files = 0
    $dirs = 0

    # 项目会话（jsonl + UUID 目录）
    if (Test-Path $ProjectsDir) {
        foreach ($projectDir in Get-ChildItem -Path $ProjectsDir -Directory -ErrorAction SilentlyContinue) {
            foreach ($f in Get-ChildItem -Path $projectDir.FullName -Filter "*.jsonl" -File -ErrorAction SilentlyContinue) {
                $bytes += $f.Length
                $files++
            }
            $uuidPattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
            $sessionDirs = Get-ChildItem -Path $projectDir.FullName -Directory -ErrorAction SilentlyContinue |
                           Where-Object { $_.Name -match $uuidPattern -and $_.Name -ne "memory" }
            foreach ($d in $sessionDirs) {
                $dirFiles = @(Get-ChildItem -Path $d.FullName -Recurse -File -ErrorAction SilentlyContinue)
                $size = ($dirFiles | Measure-Object -Property Length -Sum).Sum
                if ($null -ne $size) { $bytes += $size }
                $files += $dirFiles.Count
                $dirs++
            }
        }
    }

    # 递归目录
    foreach ($target in $CleanTargets) {
        $path = Join-Path $ClaudeDir $target.Dir
        if (Test-Path $path) {
            foreach ($f in Get-ChildItem -Path $path -File -Recurse -ErrorAction SilentlyContinue) {
                $bytes += $f.Length
                $files++
            }
        }
    }

    # 单独文件
    foreach ($item in $SingleFiles) {
        $fp = Join-Path $ClaudeDir $item.Name
        if (Test-Path $fp) {
            $bytes += (Get-Item $fp).Length
            $files++
        }
    }

    # 安全警告状态文件（通配）
    foreach ($f in Get-ChildItem -Path $ClaudeDir -Filter "security_warnings_state_*.json" -File -ErrorAction SilentlyContinue) {
        $bytes += $f.Length
        $files++
    }

    # 配置备份
    $backupsPath = Join-Path $ClaudeDir "backups"
    if (Test-Path $backupsPath) {
        foreach ($f in Get-ChildItem -Path $backupsPath -Filter ".claude.json.backup.*" -File -ErrorAction SilentlyContinue) {
            $bytes += $f.Length
            $files++
        }
    }

    return @{Bytes=$bytes; Files=$files; Dirs=$dirs}
}

<#
.SYNOPSIS
    按通配符删除指定目录下的文件（非递归）
#>
function Remove-MatchingFiles {
    param(
        [string]$Path,
        [string]$Filter,
        [string]$Label,
        [bool]$DryRun
    )

    if (-not (Test-Path $Path)) { return @{Count=0; Bytes=0} }

    $files = Get-ChildItem -Path $Path -Filter $Filter -File -ErrorAction SilentlyContinue
    $count = 0
    $bytes = 0

    foreach ($file in $files) {
        $bytes += $file.Length
        $count++
        if (-not $DryRun) {
            try {
                Remove-Item -Path $file.FullName -Force -ErrorAction Stop
            } catch {
                $script:failCount++
            }
        }
    }

    if ($count -gt 0) {
        Write-Host "  $Label`: $count 个文件 ($(Format-Bytes $bytes))"
    }

    return @{Count=$count; Bytes=$bytes}
}

<#
.SYNOPSIS
    递归清理指定目录下的所有文件
#>
function Remove-DirContents {
    param(
        [string]$Path,
        [string]$Label,
        [bool]$DryRun
    )

    if (-not (Test-Path $Path)) { return @{Count=0; Bytes=0} }

    $files = Get-ChildItem -Path $Path -File -Recurse -ErrorAction SilentlyContinue
    $count = 0
    $bytes = 0

    foreach ($file in $files) {
        $bytes += $file.Length
        $count++
        if (-not $DryRun) {
            try {
                Remove-Item -Path $file.FullName -Force -ErrorAction Stop
            } catch {
                $script:failCount++
            }
        }
    }

    if ($count -gt 0) {
        Write-Host "  $Label`: $count 个文件 ($(Format-Bytes $bytes))"
    }

    return @{Count=$count; Bytes=$bytes}
}

<#
.SYNOPSIS
    清理指定目录下的空子目录（从最深层开始）
#>
function Remove-EmptyDirectories {
    param(
        [string]$Path,
        [string]$Label,
        [bool]$DryRun
    )

    if (-not (Test-Path $Path)) { return 0 }

    $emptyDirs = Get-ChildItem -Path $Path -Directory -Recurse -ErrorAction SilentlyContinue |
                 Where-Object { (Get-ChildItem -Path $_.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0 } |
                 Sort-Object -Property FullName -Descending

    $count = 0

    foreach ($dir in $emptyDirs) {
        $count++
        if (-not $DryRun) {
            try {
                Remove-Item -Path $dir.FullName -Force -ErrorAction Stop
            } catch {
                $script:failCount++
            }
        }
    }

    if ($count -gt 0) {
        Write-Host "  $Label`: $count 个空目录"
    }

    return $count
}

# ============================================================
# 主程序开始 - 综合菜单
# ============================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Claude Code 缓存清理工具" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "扫描中..." -ForegroundColor Gray

$preview = Get-CleanupPreview

Write-Host ""
Write-Host "当前可清理约 $(Format-Bytes $preview.Bytes)（$($preview.Files) 个文件，$($preview.Dirs) 个会话目录）" -ForegroundColor Green
Write-Host ""
Write-Host "请选择操作：" -ForegroundColor Yellow
Write-Host "  [1] 预览（干运行，不删文件）                              - 推荐先跑一次"
Write-Host "  [2] 执行清理（基础：会话/缓存/临时数据）"
Write-Host "  [3] 执行清理 + 清理用户配置 .claude.json                  - 重置使用统计"
Write-Host "  [4] 执行清理 + 清理认证 .credentials.json                 - 需重新登录"
Write-Host "  [5] 执行清理 + 全清（配置 + 认证）                        - 等于重置登录状态"
Write-Host "  [Q] 退出"
Write-Host ""

$choice = Read-Host "请输入选项"
if (-not $choice) { $choice = "" }

$DryRun = $false
$CleanClaudeJson = $false
$CleanCredentials = $false

switch ($choice.ToUpper()) {
    "1" { $DryRun = $true }
    "2" { $DryRun = $false }
    "3" { $DryRun = $false; $CleanClaudeJson = $true }
    "4" { $DryRun = $false; $CleanCredentials = $true }
    "5" { $DryRun = $false; $CleanClaudeJson = $true; $CleanCredentials = $true }
    "Q" {
        Write-Host "已退出" -ForegroundColor Gray
        exit 0
    }
    default {
        Write-Host "无效选项，已退出" -ForegroundColor Red
        exit 0
    }
}

Write-Host ""

# 破坏性操作（3/4/5）先做一次详细警告
if ($CleanClaudeJson -or $CleanCredentials) {
    Write-Host "注意：此次操作将额外删除以下关键文件：" -ForegroundColor Red
    if ($CleanClaudeJson) {
        Write-Host "  - .claude.json：删除后使用统计、提示历史将被重置" -ForegroundColor Yellow
    }
    if ($CleanCredentials) {
        Write-Host "  - .credentials.json：删除后下次启动需要重新登录 Claude Code" -ForegroundColor Yellow
    }
    Write-Host ""
    $confirm2 = Read-Host "确认执行？(输入 Y 继续，其他键取消)"
    if ($confirm2 -ne "Y" -and $confirm2 -ne "y") {
        Write-Host "操作已取消" -ForegroundColor Yellow
        exit 0
    }
    Write-Host ""
}

# 显示运行模式 + 执行模式下的最终确认
if ($DryRun) {
    Write-Host "=== 干运行模式（仅预览，不会删除文件） ===" -ForegroundColor Yellow
    Write-Host ""
} else {
    Write-Host "=== 执行模式（将实际删除文件） ===" -ForegroundColor Red
    Write-Host "提示：执行清理前会先关闭正在运行的 Claude Code 进程" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "警告：即将删除文件，此操作不可恢复！" -ForegroundColor Red
    $confirm = Read-Host "确认继续？(输入 Y 继续，其他键取消)"
    if ($confirm -ne "Y" -and $confirm -ne "y") {
        Write-Host "操作已取消" -ForegroundColor Yellow
        exit 0
    }
    Write-Host ""
}

# 执行模式下先关闭 Claude Code 进程，避免文件占用
if (-not $DryRun) {
    $processResult = Stop-ClaudeCodeProcesses
    if ($processResult.Remaining -gt 0) {
        Write-Host "仍有 Claude Code 进程未退出，请手动关闭后重试。" -ForegroundColor Red
        Write-Host ""
        Write-Host "按任意键退出..." -ForegroundColor Gray
        [void][System.Console]::ReadKey($true)
        exit 1
    }
}

# 初始化统计变量
$totalFiles = 0
$totalBytes = 0

# ============================================================
# 第一部分：清理项目会话日志
# ============================================================
Write-Host "[项目/会话日志]"

if (Test-Path $ProjectsDir) {
    $projectDirs = Get-ChildItem -Path $ProjectsDir -Directory -ErrorAction SilentlyContinue

    foreach ($projectDir in $projectDirs) {
        $projectName = $projectDir.Name
        $projectFiles = 0
        $projectBytes = 0

        # 清理会话日志文件（.jsonl）
        $jsonlFiles = Get-ChildItem -Path $projectDir.FullName -Filter "*.jsonl" -File -ErrorAction SilentlyContinue
        foreach ($file in $jsonlFiles) {
            $projectBytes += $file.Length
            $projectFiles++
            if (-not $DryRun) {
                try {
                    Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                } catch {
                    $script:failCount++
                }
            }
        }

        # 清理 UUID 格式的会话目录（排除 memory 目录）
        $uuidPattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        $sessionDirs = Get-ChildItem -Path $projectDir.FullName -Directory -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -match $uuidPattern -and $_.Name -ne "memory" }

        foreach ($dir in $sessionDirs) {
            $dirContent = Get-ChildItem -Path $dir.FullName -Recurse -File -ErrorAction SilentlyContinue
            $dirSize = ($dirContent | Measure-Object -Property Length -Sum).Sum
            if ($null -eq $dirSize) { $dirSize = 0 }
            $dirFileCount = ($dirContent | Measure-Object).Count

            $projectBytes += $dirSize
            $projectFiles += $dirFileCount
            if (-not $DryRun) {
                try {
                    Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction Stop
                } catch {
                    $script:failCount++
                }
            }
        }

        # 显示项目统计信息
        if ($projectFiles -gt 0) {
            Write-Host "  $projectName`: $projectFiles 个文件 ($(Format-Bytes $projectBytes))"
            $totalFiles += $projectFiles
            $totalBytes += $projectBytes
        }
    }
}
Write-Host ""

# ============================================================
# 第二部分：清理其他临时数据（表驱动）
# ============================================================
Write-Host "[其他临时数据]"

foreach ($target in $CleanTargets) {
    $path = Join-Path $ClaudeDir $target.Dir
    $result = Remove-DirContents -Path $path -Label "$($target.Label)/" -DryRun $DryRun
    $totalFiles += $result.Count
    $totalBytes += $result.Bytes
}

# 独立文件
foreach ($item in $SingleFiles) {
    $fp = Join-Path $ClaudeDir $item.Name
    if (Test-Path $fp) {
        $fileSize = (Get-Item $fp).Length
        $totalFiles++
        $totalBytes += $fileSize
        Write-Host "  $($item.Label): 1 个文件 ($(Format-Bytes $fileSize))"
        if (-not $DryRun) {
            try {
                Remove-Item -Path $fp -Force -ErrorAction Stop
            } catch {
                $script:failCount++
            }
        }
    }
}

# 安全警告状态文件（通配）
$result = Remove-MatchingFiles -Path $ClaudeDir -Filter "security_warnings_state_*.json" -Label "安全警告状态" -DryRun $DryRun
$totalFiles += $result.Count
$totalBytes += $result.Bytes

# 配置备份
$result = Remove-MatchingFiles -Path (Join-Path $ClaudeDir "backups") -Filter ".claude.json.backup.*" -Label "配置备份" -DryRun $DryRun
$totalFiles += $result.Count
$totalBytes += $result.Bytes

Write-Host ""

# ============================================================
# 清理空目录
# ============================================================
Write-Host "[清理空目录]"

$emptyDirCount = 0

foreach ($target in $CleanTargets) {
    $path = Join-Path $ClaudeDir $target.Dir
    $emptyDirCount += Remove-EmptyDirectories -Path $path -Label "$($target.Label)/" -DryRun $DryRun
}

# 项目目录下的空 UUID 目录
if (Test-Path $ProjectsDir) {
    $projectDirs = Get-ChildItem -Path $ProjectsDir -Directory -ErrorAction SilentlyContinue
    foreach ($projectDir in $projectDirs) {
        $emptyDirCount += Remove-EmptyDirectories -Path $projectDir.FullName -Label "$($projectDir.Name)/" -DryRun $DryRun
    }
}

if ($emptyDirCount -eq 0) {
    Write-Host "  没有找到空目录" -ForegroundColor Gray
}

Write-Host ""

# ============================================================
# 第三部分：特殊清理项（用户配置/认证）
# ============================================================
if ($CleanClaudeJson -or $CleanCredentials) {
    Write-Host "[特殊清理项]" -ForegroundColor Yellow

    if ($CleanClaudeJson) {
        $claudeJsonFile = Join-Path $ClaudeDir ".claude.json"
        if (Test-Path $claudeJsonFile) {
            $fileSize = (Get-Item $claudeJsonFile).Length
            $totalFiles++
            $totalBytes += $fileSize
            Write-Host "  用户配置: 1 个文件 ($(Format-Bytes $fileSize))" -ForegroundColor Yellow
            if (-not $DryRun) {
                try {
                    Remove-Item -Path $claudeJsonFile -Force -ErrorAction Stop
                    Write-Host "  ⚠ 用户配置已删除，使用统计和提示历史将重置" -ForegroundColor Red
                } catch {
                    $script:failCount++
                    Write-Host "  删除失败: $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "  ⚠ 预览：将删除用户配置（User ID、统计等）" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  用户配置文件不存在" -ForegroundColor Gray
        }
    }

    if ($CleanCredentials) {
        $credFile = Join-Path $ClaudeDir ".credentials.json"
        if (Test-Path $credFile) {
            $fileSize = (Get-Item $credFile).Length
            $totalFiles++
            $totalBytes += $fileSize
            Write-Host "  认证凭据: 1 个文件 ($(Format-Bytes $fileSize))" -ForegroundColor Yellow
            if (-not $DryRun) {
                try {
                    Remove-Item -Path $credFile -Force -ErrorAction Stop
                    Write-Host "  ⚠ 认证凭据已删除，下次启动需要重新登录" -ForegroundColor Red
                } catch {
                    $script:failCount++
                    Write-Host "  删除失败: $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "  ⚠ 预览：将删除认证凭据（需重新登录）" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  认证凭据文件不存在" -ForegroundColor Gray
        }
    }

    Write-Host ""
}

# ============================================================
# 显示清理摘要
# ============================================================
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  清理摘要" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "文件数量: $totalFiles"
if ($emptyDirCount -gt 0) {
    Write-Host "空目录数: $emptyDirCount"
}
Write-Host "节省空间: $(Format-Bytes $totalBytes)"
if ($script:failCount -gt 0) {
    Write-Host "删除失败: $script:failCount" -ForegroundColor Red
}
Write-Host ""

# 根据模式显示不同的提示信息
if ($DryRun) {
    if (($totalFiles + $emptyDirCount) -gt 0) {
        Write-Host "这是预览结果，文件尚未删除。" -ForegroundColor Yellow
        Write-Host "如需实际删除，请重新运行脚本并选择 [2]~[5]。" -ForegroundColor Yellow
    } else {
        Write-Host "没有找到需要清理的文件。" -ForegroundColor Green
    }
} else {
    if (($totalFiles + $emptyDirCount) -gt 0) {
        Write-Host "清理完成！" -ForegroundColor Green
    } else {
        Write-Host "没有找到需要清理的文件。" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
