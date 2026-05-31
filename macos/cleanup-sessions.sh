#!/usr/bin/env bash
#
# Claude Code 缓存清理工具 (macOS / Bash 版本)
#
# 自动清理 Claude Code 产生的会话数据和临时文件，释放磁盘空间。
# 启动时预扫描显示可清理空间，通过单一综合菜单一次选择清理范围。
#
# 版本：3.0 (对齐 Windows PowerShell 版本)
# 编码：UTF-8 (无 BOM)

set -u

CLAUDE_DIR="$HOME/.claude"
PROJECTS_DIR="$CLAUDE_DIR/projects"

# 递归清理目标：(目录名|中文标签)
CLEAN_TARGETS=(
  "debug|调试"
  "shell-snapshots|shell快照"
  "file-history|文件历史"
  "todos|待办事项"
  "plans|计划"
  "tasks|任务"
  "paste-cache|粘贴缓存"
  "image-cache|图片缓存"
  "cache|通用缓存"
  "telemetry|遥测数据"
  "statsig|Statsig缓存"
  "downloads|下载"
  "session-env|会话环境"
)

# ClaudeDir 根目录下单独删除的独立文件：(文件名|中文标签)
SINGLE_FILES=(
  "history.jsonl|命令历史"
  "stats-cache.json|统计缓存"
  "mcp-needs-auth-cache.json|MCP认证缓存"
)

# 终端着色（仅在 TTY 时启用）
if [ -t 1 ]; then
  C_CYAN=$'\033[36m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_GRAY=$'\033[90m'
  C_RESET=$'\033[0m'
else
  C_CYAN=""; C_YELLOW=""; C_RED=""; C_GREEN=""; C_GRAY=""; C_RESET=""
fi

# 删除失败计数（全局）
fail_count=0

# 函数返回值（避免子 shell 丢失 fail_count 增量）
_ret_count=0
_ret_bytes=0
_ret_files=0

# ============================================================
# 工具函数
# ============================================================

format_bytes() {
  awk -v b="$1" 'BEGIN {
    if (b >= 1073741824) printf "%.1f GB", b / 1073741824
    else if (b >= 1048576) printf "%.1f MB", b / 1048576
    else if (b >= 1024)    printf "%.1f KB", b / 1024
    else                    printf "%d B", b
  }'
}

stat_size() {
  stat -f%z "$1" 2>/dev/null || echo 0
}

# 统计目录递归大小和文件数，写入 _ret_bytes / _ret_files
dir_stats() {
  local path=$1
  _ret_bytes=0
  _ret_files=0
  [ -d "$path" ] || return
  local f sz
  while IFS= read -r -d '' f; do
    sz=$(stat_size "$f")
    _ret_bytes=$((_ret_bytes + sz))
    _ret_files=$((_ret_files + 1))
  done < <(find "$path" -type f -print0 2>/dev/null)
}

# 关闭 Claude Code 桌面进程（CLI 无需关闭）
stop_claude_processes() {
  echo "[进程处理]"
  local pids
  pids=$(pgrep -x "Claude" 2>/dev/null || true)
  if [ -z "$pids" ]; then
    echo "  ${C_GRAY}未发现正在运行的 Claude Code 进程${C_RESET}"
    echo ""
    return 0
  fi

  local count
  count=$(printf "%s\n" "$pids" | wc -l | tr -d ' ')
  local pid_list
  pid_list=$(printf "%s " $pids)
  echo "  ${C_YELLOW}发现 $count 个 Claude Code 进程 (PID: ${pid_list% })${C_RESET}"
  echo "  ${C_YELLOW}正在关闭 Claude Code 相关进程...${C_RESET}"

  # 优先尝试优雅退出
  osascript -e 'tell application "Claude" to quit' >/dev/null 2>&1 || true
  sleep 1

  # 仍存活则强杀
  local remaining
  remaining=$(pgrep -x "Claude" 2>/dev/null || true)
  if [ -n "$remaining" ]; then
    pkill -x "Claude" 2>/dev/null || true
    sleep 1
    remaining=$(pgrep -x "Claude" 2>/dev/null || true)
  fi

  if [ -z "$remaining" ]; then
    echo "  ${C_GREEN}已结束 $count 个 Claude Code 进程${C_RESET}"
    echo ""
    return 0
  else
    local remain_count
    remain_count=$(printf "%s\n" "$remaining" | wc -l | tr -d ' ')
    local remain_list
    remain_list=$(printf "%s " $remaining)
    echo "  ${C_RED}仍有 $remain_count 个 Claude Code 进程未退出 (PID: ${remain_list% })${C_RESET}"
    echo ""
    return 1
  fi
}

# 预扫描，写入 _ret_bytes / _ret_files / _ret_count（_ret_count = 会话目录数）
get_cleanup_preview() {
  _ret_bytes=0
  _ret_files=0
  _ret_count=0

  local project_dir f d name sz path target dir

  # 项目会话
  if [ -d "$PROJECTS_DIR" ]; then
    while IFS= read -r -d '' project_dir; do
      while IFS= read -r -d '' f; do
        sz=$(stat_size "$f")
        _ret_bytes=$((_ret_bytes + sz))
        _ret_files=$((_ret_files + 1))
      done < <(find "$project_dir" -maxdepth 1 -name "*.jsonl" -type f -print0 2>/dev/null)

      while IFS= read -r -d '' d; do
        name=$(basename "$d")
        [ "$name" = "memory" ] && continue
        if [[ "$name" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
          # 保存当前累加值，调用 dir_stats 后会被覆盖
          local saved_bytes=$_ret_bytes
          local saved_files=$_ret_files
          local saved_count=$_ret_count
          dir_stats "$d"
          _ret_bytes=$((saved_bytes + _ret_bytes))
          _ret_files=$((saved_files + _ret_files))
          _ret_count=$((saved_count + 1))
        fi
      done < <(find "$project_dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    done < <(find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
  fi

  # 递归目录
  for target in "${CLEAN_TARGETS[@]}"; do
    dir=${target%%|*}
    path="$CLAUDE_DIR/$dir"
    if [ -d "$path" ]; then
      while IFS= read -r -d '' f; do
        sz=$(stat_size "$f")
        _ret_bytes=$((_ret_bytes + sz))
        _ret_files=$((_ret_files + 1))
      done < <(find "$path" -type f -print0 2>/dev/null)
    fi
  done

  # 独立文件
  local item fname fp
  for item in "${SINGLE_FILES[@]}"; do
    fname=${item%%|*}
    fp="$CLAUDE_DIR/$fname"
    if [ -f "$fp" ]; then
      sz=$(stat_size "$fp")
      _ret_bytes=$((_ret_bytes + sz))
      _ret_files=$((_ret_files + 1))
    fi
  done

  # 安全警告状态文件
  while IFS= read -r -d '' f; do
    sz=$(stat_size "$f")
    _ret_bytes=$((_ret_bytes + sz))
    _ret_files=$((_ret_files + 1))
  done < <(find "$CLAUDE_DIR" -maxdepth 1 -name "security_warnings_state_*.json" -type f -print0 2>/dev/null)

  # 配置备份
  if [ -d "$CLAUDE_DIR/backups" ]; then
    while IFS= read -r -d '' f; do
      sz=$(stat_size "$f")
      _ret_bytes=$((_ret_bytes + sz))
      _ret_files=$((_ret_files + 1))
    done < <(find "$CLAUDE_DIR/backups" -maxdepth 1 -name ".claude.json.backup.*" -type f -print0 2>/dev/null)
  fi
}

# 按通配符删除指定目录下的文件（非递归），结果写入 _ret_count / _ret_bytes
remove_matching_files() {
  local path=$1 pattern=$2 label=$3 dry_run=$4
  _ret_count=0
  _ret_bytes=0
  [ -d "$path" ] || return
  local f sz
  while IFS= read -r -d '' f; do
    sz=$(stat_size "$f")
    _ret_bytes=$((_ret_bytes + sz))
    _ret_count=$((_ret_count + 1))
    if [ "$dry_run" != "true" ]; then
      rm -f "$f" 2>/dev/null || fail_count=$((fail_count + 1))
    fi
  done < <(find "$path" -maxdepth 1 -name "$pattern" -type f -print0 2>/dev/null)
  if [ "$_ret_count" -gt 0 ]; then
    echo "  $label: $_ret_count 个文件 ($(format_bytes $_ret_bytes))"
  fi
}

# 递归清理指定目录下的所有文件，结果写入 _ret_count / _ret_bytes
remove_dir_contents() {
  local path=$1 label=$2 dry_run=$3
  _ret_count=0
  _ret_bytes=0
  [ -d "$path" ] || return
  local f sz
  while IFS= read -r -d '' f; do
    sz=$(stat_size "$f")
    _ret_bytes=$((_ret_bytes + sz))
    _ret_count=$((_ret_count + 1))
    if [ "$dry_run" != "true" ]; then
      rm -f "$f" 2>/dev/null || fail_count=$((fail_count + 1))
    fi
  done < <(find "$path" -type f -print0 2>/dev/null)
  if [ "$_ret_count" -gt 0 ]; then
    echo "  $label: $_ret_count 个文件 ($(format_bytes $_ret_bytes))"
  fi
}

# 清理空目录（深度优先），结果写入 _ret_count
remove_empty_directories() {
  local path=$1 label=$2 dry_run=$3
  _ret_count=0
  [ -d "$path" ] || return
  local d
  while IFS= read -r -d '' d; do
    [ "$d" = "$path" ] && continue
    _ret_count=$((_ret_count + 1))
    if [ "$dry_run" != "true" ]; then
      rmdir "$d" 2>/dev/null || fail_count=$((fail_count + 1))
    fi
  done < <(find "$path" -depth -type d -empty -print0 2>/dev/null)
  if [ "$_ret_count" -gt 0 ]; then
    echo "  $label: $_ret_count 个空目录"
  fi
}

# ============================================================
# 主程序开始 - 综合菜单
# ============================================================

echo "${C_CYAN}========================================${C_RESET}"
echo "${C_CYAN}  Claude Code 缓存清理工具${C_RESET}"
echo "${C_CYAN}========================================${C_RESET}"
echo ""
echo "${C_GRAY}扫描中...${C_RESET}"

get_cleanup_preview
preview_bytes=$_ret_bytes
preview_files=$_ret_files
preview_dirs=$_ret_count

echo ""
echo "${C_GREEN}当前可清理约 $(format_bytes $preview_bytes)（$preview_files 个文件，$preview_dirs 个会话目录）${C_RESET}"
echo ""
echo "${C_YELLOW}请选择操作：${C_RESET}"
echo "  [1] 预览（干运行，不删文件）                              - 推荐先跑一次"
echo "  [2] 执行清理（基础：会话/缓存/临时数据）"
echo "  [3] 执行清理 + 清理用户配置 .claude.json                  - 重置使用统计"
echo "  [4] 执行清理 + 清理认证 .credentials.json                 - 需重新登录"
echo "  [5] 执行清理 + 全清（配置 + 认证）                        - 等于重置登录状态"
echo "  [Q] 退出"
echo ""

read -rp "请输入选项: " choice
choice=$(printf "%s" "${choice:-}" | tr '[:lower:]' '[:upper:]')

DRY_RUN=false
CLEAN_CLAUDE_JSON=false
CLEAN_CREDENTIALS=false

case "$choice" in
  1) DRY_RUN=true ;;
  2) ;;
  3) CLEAN_CLAUDE_JSON=true ;;
  4) CLEAN_CREDENTIALS=true ;;
  5) CLEAN_CLAUDE_JSON=true; CLEAN_CREDENTIALS=true ;;
  Q) echo "${C_GRAY}已退出${C_RESET}"; exit 0 ;;
  *) echo "${C_RED}无效选项，已退出${C_RESET}"; exit 0 ;;
esac

echo ""

# 破坏性操作（3/4/5）先做一次详细警告
if $CLEAN_CLAUDE_JSON || $CLEAN_CREDENTIALS; then
  echo "${C_RED}注意：此次操作将额外删除以下关键文件：${C_RESET}"
  $CLEAN_CLAUDE_JSON && echo "  ${C_YELLOW}- .claude.json：删除后使用统计、提示历史将被重置${C_RESET}"
  $CLEAN_CREDENTIALS && echo "  ${C_YELLOW}- .credentials.json：删除后下次启动需要重新登录 Claude Code${C_RESET}"
  echo ""
  read -rp "确认执行？(输入 Y 继续，其他键取消): " confirm2
  if [ "$confirm2" != "Y" ] && [ "$confirm2" != "y" ]; then
    echo "${C_YELLOW}操作已取消${C_RESET}"
    exit 0
  fi
  echo ""
fi

# 显示运行模式 + 执行模式下的最终确认
if $DRY_RUN; then
  echo "${C_YELLOW}=== 干运行模式（仅预览，不会删除文件） ===${C_RESET}"
  echo ""
else
  echo "${C_RED}=== 执行模式（将实际删除文件） ===${C_RESET}"
  echo "${C_YELLOW}提示：执行清理前会先关闭正在运行的 Claude Code 进程${C_RESET}"
  echo ""
  echo "${C_RED}警告：即将删除文件，此操作不可恢复！${C_RESET}"
  read -rp "确认继续？(输入 Y 继续，其他键取消): " confirm
  if [ "$confirm" != "Y" ] && [ "$confirm" != "y" ]; then
    echo "${C_YELLOW}操作已取消${C_RESET}"
    exit 0
  fi
  echo ""
fi

# 执行模式下先关闭 Claude Code 进程
if ! $DRY_RUN; then
  if ! stop_claude_processes; then
    echo "${C_RED}仍有 Claude Code 进程未退出，请手动关闭后重试。${C_RESET}"
    echo ""
    read -rsn1 -p "按任意键退出..."
    echo ""
    exit 1
  fi
fi

# 初始化统计
total_files=0
total_bytes=0

# ============================================================
# 第一部分：清理项目会话日志
# ============================================================
echo "[项目/会话日志]"

if [ -d "$PROJECTS_DIR" ]; then
  while IFS= read -r -d '' project_dir; do
    project_name=$(basename "$project_dir")
    project_files=0
    project_bytes=0

    # 清理会话日志文件（.jsonl）
    while IFS= read -r -d '' f; do
      sz=$(stat_size "$f")
      project_bytes=$((project_bytes + sz))
      project_files=$((project_files + 1))
      if ! $DRY_RUN; then
        rm -f "$f" 2>/dev/null || fail_count=$((fail_count + 1))
      fi
    done < <(find "$project_dir" -maxdepth 1 -name "*.jsonl" -type f -print0 2>/dev/null)

    # 清理 UUID 会话目录（排除 memory）
    while IFS= read -r -d '' d; do
      name=$(basename "$d")
      [ "$name" = "memory" ] && continue
      if [[ "$name" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        dir_stats "$d"
        project_bytes=$((project_bytes + _ret_bytes))
        project_files=$((project_files + _ret_files))
        if ! $DRY_RUN; then
          rm -rf "$d" 2>/dev/null || fail_count=$((fail_count + 1))
        fi
      fi
    done < <(find "$project_dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

    if [ "$project_files" -gt 0 ]; then
      echo "  $project_name: $project_files 个文件 ($(format_bytes $project_bytes))"
      total_files=$((total_files + project_files))
      total_bytes=$((total_bytes + project_bytes))
    fi
  done < <(find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
fi
echo ""

# ============================================================
# 第二部分：清理其他临时数据（表驱动）
# ============================================================
echo "[其他临时数据]"

for target in "${CLEAN_TARGETS[@]}"; do
  dir=${target%%|*}
  label=${target#*|}
  path="$CLAUDE_DIR/$dir"
  remove_dir_contents "$path" "$label/" "$DRY_RUN"
  total_files=$((total_files + _ret_count))
  total_bytes=$((total_bytes + _ret_bytes))
done

# 独立文件
for item in "${SINGLE_FILES[@]}"; do
  fname=${item%%|*}
  label=${item#*|}
  fp="$CLAUDE_DIR/$fname"
  if [ -f "$fp" ]; then
    sz=$(stat_size "$fp")
    total_files=$((total_files + 1))
    total_bytes=$((total_bytes + sz))
    echo "  $label: 1 个文件 ($(format_bytes $sz))"
    if ! $DRY_RUN; then
      rm -f "$fp" 2>/dev/null || fail_count=$((fail_count + 1))
    fi
  fi
done

# 安全警告状态文件（通配）
remove_matching_files "$CLAUDE_DIR" "security_warnings_state_*.json" "安全警告状态" "$DRY_RUN"
total_files=$((total_files + _ret_count))
total_bytes=$((total_bytes + _ret_bytes))

# 配置备份
remove_matching_files "$CLAUDE_DIR/backups" ".claude.json.backup.*" "配置备份" "$DRY_RUN"
total_files=$((total_files + _ret_count))
total_bytes=$((total_bytes + _ret_bytes))

echo ""

# ============================================================
# 清理空目录
# ============================================================
echo "[清理空目录]"

empty_dir_count=0

for target in "${CLEAN_TARGETS[@]}"; do
  dir=${target%%|*}
  label=${target#*|}
  path="$CLAUDE_DIR/$dir"
  remove_empty_directories "$path" "$label/" "$DRY_RUN"
  empty_dir_count=$((empty_dir_count + _ret_count))
done

# 项目目录下的空 UUID 目录
if [ -d "$PROJECTS_DIR" ]; then
  while IFS= read -r -d '' project_dir; do
    project_name=$(basename "$project_dir")
    remove_empty_directories "$project_dir" "$project_name/" "$DRY_RUN"
    empty_dir_count=$((empty_dir_count + _ret_count))
  done < <(find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
fi

if [ "$empty_dir_count" -eq 0 ]; then
  echo "  ${C_GRAY}没有找到空目录${C_RESET}"
fi

echo ""

# ============================================================
# 第三部分：特殊清理项（用户配置/认证）
# ============================================================
if $CLEAN_CLAUDE_JSON || $CLEAN_CREDENTIALS; then
  echo "${C_YELLOW}[特殊清理项]${C_RESET}"

  if $CLEAN_CLAUDE_JSON; then
    fp="$CLAUDE_DIR/.claude.json"
    if [ -f "$fp" ]; then
      sz=$(stat_size "$fp")
      total_files=$((total_files + 1))
      total_bytes=$((total_bytes + sz))
      echo "  ${C_YELLOW}用户配置: 1 个文件 ($(format_bytes $sz))${C_RESET}"
      if ! $DRY_RUN; then
        if rm -f "$fp" 2>/dev/null; then
          echo "  ${C_RED}⚠ 用户配置已删除，使用统计和提示历史将重置${C_RESET}"
        else
          fail_count=$((fail_count + 1))
          echo "  ${C_RED}删除失败${C_RESET}"
        fi
      else
        echo "  ${C_YELLOW}⚠ 预览：将删除用户配置（User ID、统计等）${C_RESET}"
      fi
    else
      echo "  ${C_GRAY}用户配置文件不存在${C_RESET}"
    fi
  fi

  if $CLEAN_CREDENTIALS; then
    fp="$CLAUDE_DIR/.credentials.json"
    if [ -f "$fp" ]; then
      sz=$(stat_size "$fp")
      total_files=$((total_files + 1))
      total_bytes=$((total_bytes + sz))
      echo "  ${C_YELLOW}认证凭据: 1 个文件 ($(format_bytes $sz))${C_RESET}"
      if ! $DRY_RUN; then
        if rm -f "$fp" 2>/dev/null; then
          echo "  ${C_RED}⚠ 认证凭据已删除，下次启动需要重新登录${C_RESET}"
        else
          fail_count=$((fail_count + 1))
          echo "  ${C_RED}删除失败${C_RESET}"
        fi
      else
        echo "  ${C_YELLOW}⚠ 预览：将删除认证凭据（需重新登录）${C_RESET}"
      fi
    else
      echo "  ${C_GRAY}认证凭据文件不存在${C_RESET}"
    fi
  fi

  echo ""
fi

# ============================================================
# 显示清理摘要
# ============================================================
echo "${C_CYAN}========================================${C_RESET}"
echo "${C_CYAN}  清理摘要${C_RESET}"
echo "${C_CYAN}========================================${C_RESET}"
echo "文件数量: $total_files"
[ "$empty_dir_count" -gt 0 ] && echo "空目录数: $empty_dir_count"
echo "节省空间: $(format_bytes $total_bytes)"
[ "$fail_count" -gt 0 ] && echo "${C_RED}删除失败: $fail_count${C_RESET}"
echo ""

if $DRY_RUN; then
  if [ $((total_files + empty_dir_count)) -gt 0 ]; then
    echo "${C_YELLOW}这是预览结果，文件尚未删除。${C_RESET}"
    echo "${C_YELLOW}如需实际删除，请重新运行脚本并选择 [2]~[5]。${C_RESET}"
  else
    echo "${C_GREEN}没有找到需要清理的文件。${C_RESET}"
  fi
else
  if [ $((total_files + empty_dir_count)) -gt 0 ]; then
    echo "${C_GREEN}清理完成！${C_RESET}"
  else
    echo "${C_GREEN}没有找到需要清理的文件。${C_RESET}"
  fi
fi

echo ""
read -rsn1 -p "按任意键退出..."
echo ""
