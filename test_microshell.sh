#!/bin/sh

PROG=./microshell

COL_GREEN='\033[0;32m'
COL_RED='\033[0;31m'
COL_YELLOW='\033[0;33m'
COL_RESET='\033[0m'

if [ ! -x "$PROG" ]; then
    printf "${COL_RED}Error:${COL_RESET} %s 不存在或不可执行\n" "$PROG"
    exit 1
fi

TMPDIR="./microshell_test_tmp.$$"
mkdir -p "$TMPDIR" || {
    echo "无法创建临时目录 $TMPDIR"
    exit 1
}
trap 'rm -rf "$TMPDIR"' INT TERM EXIT

TOTAL=0
OK=0
KO=0

echo "==============================================="
echo "       microshell 自动测试脚本 (sh)"
echo "  使用程序: $PROG"
echo "  临时目录: $TMPDIR"
echo "==============================================="
echo

test_cmp() {
    NAME="$1"
    MS_ARGS="$2"
    SH_CMD="$3"

    TOTAL=$((TOTAL + 1))
    printf "[@] %-40s" "$NAME"

    MS_OUT="$TMPDIR/ms_out_$TOTAL.txt"
    SH_OUT="$TMPDIR/sh_out_$TOTAL.txt"

    # microshell
    # shellcheck disable=SC2086
    eval "$PROG $MS_ARGS" >"$MS_OUT" 2>&1
    MS_RET=$?

    # /bin/sh 参考
    /bin/sh -c "$SH_CMD" >"$SH_OUT" 2>&1
    SH_RET=$?

    if diff -u "$SH_OUT" "$MS_OUT" >/dev/null 2>&1 && [ "$MS_RET" -eq "$SH_RET" ]; then
        printf " ${COL_GREEN}[OK]${COL_RESET}\n"
        OK=$((OK + 1))
    else
        printf " ${COL_RED}[KO]${COL_RESET}\n"
        KO=$((KO + 1))
        echo "    Shell cmd   : $SH_CMD"
        echo "    Microshell  : $PROG $MS_ARGS"
        echo "    Return codes: sh=$SH_RET, microshell=$MS_RET"
        echo "    --- sh_out ---"
        sed 's/^/    /' "$SH_OUT"
        echo "    --- ms_out ---"
        sed 's/^/    /' "$MS_OUT"
        echo "    -------------"
    fi
}

test_ms_exact() {
    NAME="$1"
    MS_ARGS="$2"
    EXPECT_LINE="$3"

    TOTAL=$((TOTAL + 1))
    printf "[!] %-40s" "$NAME"

    MS_OUT="$TMPDIR/ms_exact_$TOTAL.txt"
    EXP_OUT="$TMPDIR/expect_exact_$TOTAL.txt"

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
}

echo "${COL_YELLOW}== 基础命令 & 分号 ; 测试 ==${COL_RESET}"

test_cmp "simple echo" \
    "/bin/echo hello" \
    "/bin/echo hello"

test_cmp "echo multi args" \
    "/bin/echo hello world 42 microshell" \
    "/bin/echo hello world 42 microshell"

test_cmp "two commands with ;" \
    "/bin/echo first ';' /bin/echo second" \
    "/bin/echo first ; /bin/echo second"

test_cmp "three commands with ;" \
    "/bin/echo one ';' /bin/echo two ';' /bin/echo three" \
    "/bin/echo one ; /bin/echo two ; /bin/echo three"

echo
echo "${COL_YELLOW}== 管道 | 测试 ==${COL_RESET}"

test_cmp "echo | grep (match)" \
    "/bin/echo hello '|' /usr/bin/grep he" \
    "/bin/echo hello | /usr/bin/grep he"

test_cmp "pipe no match (empty output)" \
    "/bin/echo hello '|' /usr/bin/grep xyz" \
    "/bin/echo hello | /usr/bin/grep xyz"

test_cmp "pipe chain 3" \
    "/bin/echo abcdef '|' /usr/bin/grep bc '|' /usr/bin/grep b" \
    "/bin/echo abcdef | /usr/bin/grep bc | /usr/bin/grep b"

test_cmp "pipe with multi args" \
    "/bin/echo a b c d '|' /usr/bin/grep c" \
    "/bin/echo a b c d | /usr/bin/grep c"

echo
echo "${COL_YELLOW}== 混合 ; 和 | 测试 ==${COL_RESET}"

test_cmp "mix ; and | 1" \
    "/bin/echo foo ';' /bin/echo bar '|' /usr/bin/grep ba" \
    "/bin/echo foo ; /bin/echo bar | /usr/bin/grep ba"

test_cmp "mix ; and | 2" \
    "/bin/echo first '|' /usr/bin/grep fir ';' /bin/echo second" \
    "/bin/echo first | /usr/bin/grep fir ; /bin/echo second"

echo
echo "${COL_YELLOW}== cd 内建命令测试 ==${COL_RESET}"

TEST_DIR="$TMPDIR/cd_test"
mkdir -p "$TEST_DIR/dir1/dir2" || {
    echo "无法创建 $TEST_DIR/dir1/dir2"
    exit 1
}

(
    cd "$TEST_DIR" || exit 1

    test_cmp "cd success then pwd" \
        "cd dir1 ';' cd dir2 ';' /bin/pwd" \
        "cd dir1 ; cd dir2 ; /bin/pwd"

    test_ms_exact "cd no args" \
        "cd" \
        "error: cd: bad arguments"

    test_ms_exact "cd too many args" \
        "cd dir1 dir2" \
        "error: cd: bad arguments"

    NON_EXIST="no_such_dir_here"
    test_ms_exact "cd non-existing" \
        "cd $NON_EXIST" \
        "error: cd: cannot change directory to $NON_EXIST"

    test_cmp "cd then echo" \
        "cd dir1 ';' /bin/echo inside_dir1" \
        "cd dir1 ; /bin/echo inside_dir1"
)

echo
echo "${COL_YELLOW}== execve 失败信息测试 ==${COL_RESET}"

BAD_BIN="/this/command/does/not/exist"
test_ms_exact "execve fail message" \
    "$BAD_BIN" \
    "error: cannot execute $BAD_BIN"

echo
echo "${COL_YELLOW}== 多重管道压力测试 ==${COL_RESET}"

PIPE_NUM=30
MS_CMD="/bin/echo start"
SH_CMD="/bin/echo start"

i=0
while [ "$i" -lt "$PIPE_NUM" ]; do
    MS_CMD="$MS_CMD '|' /usr/bin/grep ."
    SH_CMD="$SH_CMD | /usr/bin/grep ."
    i=$((i + 1))
done

test_cmp "many pipes 30" \
    "$MS_CMD" \
    "$SH_CMD"

echo
echo "${COL_YELLOW}== 组合大杂烩测试 ==${COL_RESET}"

test_cmp "complex mix ; and |" \
    "/bin/echo one two three '|' /usr/bin/grep two ';' /bin/echo A B C '|' /usr/bin/grep B ';' /bin/echo end" \
    "/bin/echo one two three | /usr/bin/grep two ; /bin/echo A B C | /usr/bin/grep B ; /bin/echo end"

echo
echo "==============================================="
printf " 测试总数: %d,  ${COL_GREEN}通过: %d${COL_RESET},  ${COL_RED}失败: %d${COL_RESET}\n" "$TOTAL" "$OK" "$KO"
echo "==============================================="

[ "$KO" -ne 0 ] && exit 1
exit 0
