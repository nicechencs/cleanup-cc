#!/usr/bin/env bash
# ========================================
#   Claude Code 缓存清理工具 - macOS 启动器
# ========================================
#
# 使用方法：
#   - Finder 中双击此文件即可在 Terminal.app 中运行
#   - 首次使用前如出现 "无法执行" 提示，请执行：
#       chmod +x cleanup-sessions.sh cleanup-sessions.command
#
# ========================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SH_SCRIPT="$SCRIPT_DIR/cleanup-sessions.sh"

if [ ! -f "$SH_SCRIPT" ]; then
  echo "错误：找不到清理脚本"
  echo "路径: $SH_SCRIPT"
  echo ""
  read -rsn1 -p "按任意键退出..."
  echo ""
  exit 1
fi

bash "$SH_SCRIPT"
