#!/bin/sh

# ============================================================
#  microshell 测试脚本（POSIX sh 版本）
#  使用方法：
#     1) 把你的可执行文件命名为 "microshell"
#     2) ./test_microshell.sh
#
#  脚本会：
#     - 对多数命令：比较 microshell 与 /bin/sh 的输出(含 stderr)
#     - 对 cd / 错误信息：单独检查错误字符串是否完全符合题目要求
# ============================================================

PROG=./microshell

# 颜色输出（如果终端不支持颜色也不会出大问题）
COL_GREEN='\033[0;32m'
COL_RED='\033[0;31m'
COL_YELLOW='\033[0;33m'
COL_RESET='\033[0m'

if [ ! -x "$PROG" ]; then
    printf "${COL_RED}Error:${COL_RESET} %s 不存在或不可执行\n" "$PROG"
    printf "请先编译你的 microshell 程序，然后再运行本脚本。\n"
    exit 1
fi

# 临时目录保存输出
TMPDIR=$(mktemp -d microshell_test.XXXXXX 2>/dev/null || echo "/tmp/microshell_test.$$")
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' INT TERM EXIT

TOTAL=0
OK=0
KO=0

# 打印标题
echo "==============================================="
echo "       microshell 自动测试脚本 (sh)            "
echo "  使用程序: $PROG"
echo "  临时目录: $TMPDIR"
echo "==============================================="
echo

# ------------------------------------------------
# 工具函数：比较 microshell 和 /
