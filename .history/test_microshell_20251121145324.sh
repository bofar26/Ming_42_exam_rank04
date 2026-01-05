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
# 工具函数：比较 microshell 和 /bin/sh 的输出
# 参数：
#   $1 -> 测试名称
#   $2 -> microshell 的参数字符串 (会被 eval 进 $PROG 后边)
#   $3 -> /bin/sh -c '...' 的命令字符串
# ------------------------------------------------
test_cmp()
{
    NAME="$1"
    MS_ARGS="$2"
    SH_CMD="$3"

    TOTAL=$((TOTAL + 1))
    printf "[@] %-40s" "$NAME"

    MS_OUT="$TMPDIR/ms_out.$$"
    SH_OUT="$TMPDIR/sh_out.$$"
    DIFF_OUT="$TMPDIR/diff.$$"

    # 运行 microshell
    # shellcheck disable=SC2086
    eval "$PROG $MS_ARGS" >"$MS_OUT" 2>&1
    MS_RET=$?

    # 运行 /bin/sh
    /bin/sh -c "$SH_CMD" >"$SH_OUT" 2>&1
    SH_RET=$?

    # 比较输出与返回值
    if diff -u "$SH_OUT" "$MS_OUT" >"$DIFF_OUT" 2>&1 && [ "$MS_RET" -eq "$SH_RET" ]; then
        printf " ${COL_GREEN}[OK]${COL_RESET}\n"
        OK=$((OK + 1))
    else
        printf " ${COL_RED}[KO]${COL_RESET}\n"
        KO=$((KO + 1))
        echo "    Shell cmd   : $SH_CMD"
        echo "    Microshell  : $PROG $MS_ARGS"
        echo "    Return codes: sh=$SH_RET, microshell=$MS_RET"
        echo "    --- diff (sh_out vs ms_out) ---"
        sed 's/^/    /' "$DIFF_OUT"
        echo "    -------------------------------"
    fi

    rm -f "$MS_OUT" "$SH_OUT" "$DIFF_OUT"
}

# ------------------------------------------------
# 工具函数：只测 microshell 的输出是否与期望字符串一致
#   主要用于测试题目规定的错误信息
# 参数：
#   $1 -> 测试名称
#   $2 -> microshell 的参数字符串 (eval 到 $PROG 后面)
#   $3 -> 期望的完整输出（包含换行，脚本自动加一个 '\n'）
# ------------------------------------------------
test_ms_exact()
{
    NAME="$1"
    MS_ARGS="$2"
    EXPECT_LINE="$3"

    TOTAL=$((TOTAL + 1))
    printf "[!] %-40s" "$NAME"

    MS_OUT="$TMPDIR/ms_only_out.$$"
    EXP_OUT="$TMPDIR/expected_only_out.$$"

    printf "%s\n" "$EXPECT_LINE" >"$EXP_OUT"

    # shellcheck disable=SC2086
    eval "$PROG $MS_ARGS" >"$MS_OUT" 2>&1
    MS_RET=$?

    if diff -u "$EXP_OUT" "$MS_OUT" >/dev/null 2>&1; then
        printf " ${COL_GREEN}[OK]${COL_RESET}\n"
        OK=$((OK + 1))
    else
        printf " ${COL_RED}[KO]${COL_RESET}\n"
        KO=$((KO + 1))
        echo "    Microshell  : $PROG $MS_ARGS"
        echo "    Return code : $MS_RET"
        echo "    --- expected ---"
        sed 's/^/    /' "$EXP_OUT"
        echo "    --- got ---"
        sed 's/^/    /' "$MS_OUT"
        echo "    -------------"
    fi

    rm -f "$MS_OUT" "$EXP_OUT"
}

# ============================================================
#                    正式开始测试
# ============================================================

echo "${COL_YELLOW}== 基础命令 & 分号 ; 测试 ==${COL_RESET}"

test_cmp "simple echo" \
    "/bin/echo hello" \
    "/bin/echo hello"

test_cmp "echo with multiple args" \
    "/bin/echo hello world 42 microshell" \
    "/bin/echo hello world 42 microshell"

test_cmp "two commands with ;" \
    "/bin/echo first ';' /bin/echo second" \
    "/bin/echo first ; /bin/echo second"

test_cmp "three commands with ;" \
    "/bin/echo one ';' /bin/echo two ';' /bin/echo three" \
    "/bin/echo one ; /bin/echo two ; /bin/echo three"

test_cmp "mixed success and failure (execve fail included)" \
    "/bin/echo ok ';' /bin/echo still_ok" \
    "/bin/echo ok ; /bin/echo still_ok"

echo
echo "${COL_YELLOW}== 管道 | 测试 ==${COL_RESET}"

test_cmp "simple pipe echo | grep" \
    "/bin/echo hello '|' /usr/bin/grep he" \
    "/bin/echo hello | /usr/bin/grep he"

test_cmp "pipe no match (empty output)" \
    "/bin/echo hello '|' /usr/bin/grep xyz" \
    "/bin/echo hello | /usr/bin/grep xyz"

test_cmp "pipe chain 3 stages" \
    "/bin/echo abcdef '|' /usr/bin/grep bc '|' /usr/bin/grep b" \
    "/bin/echo abcdef | /usr/bin/grep bc | /usr/bin/grep b"

test_cmp "pipe with multiple args" \
    "/bin/echo a b c d '|' /usr/bin/grep c" \
    "/bin/echo a b c d | /usr/bin/grep c"

test_cmp "mix ; and | 1" \
    "/bin/echo foo ';' /bin/echo bar '|' /usr/bin/grep ba" \
    "/bin/echo foo ; /bin/echo bar | /usr/bin/grep ba"

test_cmp "mix ; and | 2" \
    "/bin/echo first '|' /usr/bin/grep fir ';' /bin/echo second" \
    "/bin/echo first | /usr/bin/grep fir ; /bin/echo second"

echo
echo "${COL_YELLOW}== cd 内建命令测试 ==${COL_RESET}"

# 为 cd 测试准备临时目录
TEST_DIR="$TMPDIR/cd_test_dir"
mkdir -p "$TEST_DIR/dir1/dir2" || {
    echo "无法创建测试目录 $TEST_DIR, 退出。"
    exit 1
}

# 用 cd + pwd 检查是否在同一进程中保持目录
(
    cd "$TEST_DIR" || exit 1

    # 成功 cd: cd dir1 ; cd dir2 ; /bin/pwd
    test_cmp "cd success and persist then pwd" \
        "cd dir1 ';' cd dir2 ';' /bin/pwd" \
        "cd dir1 ; cd dir2 ; /bin/pwd"

    # cd 参数错误（0 个参数）
    test_ms_exact "cd with no arguments" \
        "cd" \
        "error: cd: bad arguments"

    # cd 参数错误（超过 1 个参数）
    test_ms_exact "cd with too many arguments" \
        "cd dir1 dir2" \
        "error: cd: bad arguments"

    # cd 到不存在的目录
    NON_EXIST="this_directory_does_not_exist"
    test_ms_exact "cd to non-existing directory" \
        "cd $NON_EXIST" \
        "error: cd: cannot change directory to $NON_EXIST"

    # cd 成功后执行命令
    test_cmp "cd then echo inside new dir" \
        "cd dir1 ';' /bin/pwd" \
        "cd dir1 ; /bin/pwd"
)

echo
echo "${COL_YELLOW}== execve 失败信息测试 ==${COL_RESET}"

BAD_BIN="/this/command/does/not/exist"
test_ms_exact "execve fail prints correct error" \
    "$BAD_BIN" \
    "error: cannot execute $BAD_BIN"

echo
echo "${COL_YELLOW}== 多重管道压力测试（文件描述符泄漏检测） ==${COL_RESET}"

# 构造一个有很多个管道的命令：
# /bin/echo start | /usr/bin/grep s | /usr/bin/grep t | ... （很多次）
# 逻辑上输出没啥重要，只要不崩溃/不报错即可
build_many_pipes() {
    N="$1"         # 管道数量
    CMD_MS="/bin/echo start"
    CMD_SH="/bin/echo start"
    i=0
    while [ "$i" -lt "$N" ]; do
        CMD_MS="$CMD_MS '|' /usr/bin/grep ."
        CMD_SH="$CMD_SH | /usr/bin/grep ."
        i=$((i + 1))
    done
    echo "$CMD_MS"
    echo "$CMD_SH"
}

# 例如 50 个管道
PIPE_NUM=50
set -- $(build_many_pipes "$PIPE_NUM")
MS_BIG_PIPE="$1"
SH_BIG_PIPE="$2"

test_cmp "many pipes (${PIPE_NUM})" \
    "$MS_BIG_PIPE" \
    "$SH_BIG_PIPE"

echo
echo "${COL_YELLOW}== 组合大杂烩测试 ==${COL_RESET}"

test_cmp "complex mix ; and | and multiple args" \
    "/bin/echo one two three '|' /usr/bin/grep two ';' /bin/echo A B C '|' /usr/bin/grep B ';' /bin/echo end" \
    "/bin/echo one two three | /usr/bin/grep two ; /bin/echo A B C | /usr/bin/grep B ; /bin/echo end"

test_cmp "complex with failing grep in middle" \
    "/bin/echo hello '|' /usr/bin/grep zzz ';' /bin/echo after_fail" \
    "/bin/echo hello | /usr/bin/grep zzz ; /bin/echo after_fail"

echo
echo "==============================================="
printf " 测试总数: %d,  ${COL_GREEN}通过: %d${COL_RESET},  ${COL_RED}失败: %d${COL_RESET}\n" "$TOTAL" "$OK" "$KO"
echo "==============================================="

if [ "$KO" -ne 0 ]; then
    exit 1
fi
exit 0
