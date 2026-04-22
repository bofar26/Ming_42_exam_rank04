#!/usr/bin/env bash
set -u

BIN="./microshell"
TMPDIR=".test_tmp"
mkdir -p "$TMPDIR"

green() { printf "\033[32m%s\033[0m\n" "$*"; }
red()   { printf "\033[31m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[33m%s\033[0m\n" "$*"; }

FAILS=0
TESTS=0

run_ms() {
  : >"$TMPDIR/out_ms.txt"
  : >"$TMPDIR/err_ms.txt"
  "$BIN" "$@" >"$TMPDIR/out_ms.txt" 2>"$TMPDIR/err_ms.txt"
  echo $? >"$TMPDIR/code_ms.txt"
}

run_bash() {
  local cmd="$1"
  : >"$TMPDIR/out_bash.txt"
  : >"$TMPDIR/err_bash.txt"
  bash -c "$cmd" >"$TMPDIR/out_bash.txt" 2>"$TMPDIR/err_bash.txt"
  echo $? >"$TMPDIR/code_bash.txt"
}

assert_file_eq() {
  local a="$1" b="$2" label="$3"
  if ! diff -u "$a" "$b" >/dev/null 2>&1; then
    red "  ✗ $label differs"
    diff -u "$a" "$b" || true
    return 1
  fi
  return 0
}

assert_exit_eq_file() {
  local got exp
  got="$(cat "$TMPDIR/code_ms.txt")"
  exp="$1"
  if [[ "$got" != "$exp" ]]; then
    red "  ✗ exit code mismatch: got $got expected $exp"
    return 1
  fi
  return 0
}

test_case_compare_with_bash() {
  local name="$1"; shift
  local bash_cmd="$1"; shift
  local -a ms_args=("$@")

  ((TESTS++))
  yellow "[$TESTS] $name"

  run_ms "${ms_args[@]}"
  run_bash "$bash_cmd"

  local ok=0
  assert_file_eq "$TMPDIR/out_ms.txt" "$TMPDIR/out_bash.txt" "stdout" || ok=1
  assert_file_eq "$TMPDIR/err_ms.txt" "$TMPDIR/err_bash.txt" "stderr" || ok=1

  local ms_code bash_code
  ms_code="$(cat "$TMPDIR/code_ms.txt")"
  bash_code="$(cat "$TMPDIR/code_bash.txt")"
  if [[ "$ms_code" != "$bash_code" ]]; then
    red "  ✗ exit code differs (ms=$ms_code bash=$bash_code)"
    ok=1
  fi

  if [[ "$ok" -eq 0 ]]; then
    green "  ✓ ok"
  else
    ((FAILS++))
  fi
}

# IMPORTANT: exp_out/exp_err are strings that may contain \n.
# We compare by writing expected bytes to files, NOT by reading outputs into variables.
test_case_expect_files() {
  local name="$1"; shift
  local exp_out="$1"; shift
  local exp_err="$1"; shift
  local exp_code="$1"; shift
  local -a ms_args=("$@")

  ((TESTS++))
  yellow "[$TESTS] $name"

  run_ms "${ms_args[@]}"

  # %b makes \n in the expected strings become real newlines
  printf "%b" "$exp_out" >"$TMPDIR/out_exp.txt"
  printf "%b" "$exp_err" >"$TMPDIR/err_exp.txt"

  local ok=0
  assert_file_eq "$TMPDIR/out_ms.txt" "$TMPDIR/out_exp.txt" "stdout" || ok=1
  assert_file_eq "$TMPDIR/err_ms.txt" "$TMPDIR/err_exp.txt" "stderr" || ok=1
  assert_exit_eq_file "$exp_code" || ok=1

  if [[ "$ok" -eq 0 ]]; then
    green "  ✓ ok"
  else
    ((FAILS++))
  fi
}

if [[ ! -x "$BIN" ]]; then
  red "microshell binary not found: run make first"
  exit 1
fi

# ========= TESTS =========

test_case_compare_with_bash \
  "simple ';' sequencing" \
  "/bin/echo hello ; /bin/echo world" \
  /bin/echo hello ";" /bin/echo world

test_case_compare_with_bash \
  "exit code is last command's status" \
  "/bin/true ; /bin/false" \
  /bin/true ";" /bin/false

test_case_compare_with_bash \
  "simple pipe echo -> wc" \
  "/bin/echo -n abc | /usr/bin/wc -c" \
  /bin/echo -n abc "|" /usr/bin/wc -c

test_case_compare_with_bash \
  "multi pipe echo -> cat -> wc" \
  "/bin/echo -n abc | /bin/cat | /usr/bin/wc -c" \
  /bin/echo -n abc "|" /bin/cat "|" /usr/bin/wc -c

CDDIR="$TMPDIR/cd_target"
mkdir -p "$CDDIR"
test_case_compare_with_bash \
  "cd success affects next command" \
  "cd \"$CDDIR\" ; /bin/pwd" \
  cd "$CDDIR" ";" /bin/pwd

test_case_expect_files \
  "cd bad arguments prints correct message" \
  "" \
  "error: cd: bad arguments\n" \
  "0" \
  cd "$CDDIR" extra

test_case_expect_files \
  "cd cannot change directory prints correct message" \
  "" \
  "error: cd: cannot change directory to /no/such/dir\n" \
  "0" \
  cd /no/such/dir

# execve failure exact stderr including \n
((TESTS++))
yellow "[$TESTS] execve failure prints correct message"
run_ms /no/such/executable
printf "%b" "" >"$TMPDIR/out_exp.txt"
printf "%b" "error: cannot execute /no/such/executable\n" >"$TMPDIR/err_exp.txt"
ok=0
assert_file_eq "$TMPDIR/out_ms.txt" "$TMPDIR/out_exp.txt" "stdout" || ok=1
assert_file_eq "$TMPDIR/err_ms.txt" "$TMPDIR/err_exp.txt" "stderr" || ok=1
ms_code="$(cat "$TMPDIR/code_ms.txt")"
if [[ "$ms_code" == "0" ]]; then
  red "  ✗ exit code should be non-zero on exec failure (got $ms_code)"
  ok=1
fi
if [[ "$ok" -eq 0 ]]; then
  green "  ✓ ok"
else
  ((FAILS++))
fi

# Many pipes with low open-files limit (fd leak test)
((TESTS++))
yellow "[$TESTS] many pipes under ulimit -n 30 (fd leak test)"
set +e
(
  ulimit -n 30 || exit 2
  args=(/bin/echo -n X)
  for _ in $(seq 1 199); do
    args+=("|" /bin/cat)
  done
  args+=("|" /usr/bin/wc -c)

  "$BIN" "${args[@]}" >"$TMPDIR/out_ms.txt" 2>"$TMPDIR/err_ms.txt"
  echo $? >"$TMPDIR/code_ms.txt"
)
set -e

ok=0
printf "%b" "1\n" >"$TMPDIR/out_exp.txt"
printf "%b" "" >"$TMPDIR/err_exp.txt"
assert_file_eq "$TMPDIR/out_ms.txt" "$TMPDIR/out_exp.txt" "stdout" || ok=1
assert_file_eq "$TMPDIR/err_ms.txt" "$TMPDIR/err_exp.txt" "stderr" || ok=1
assert_exit_eq_file "0" || ok=1
if [[ "$ok" -eq 0 ]]; then
  green "  ✓ ok"
else
  ((FAILS++))
fi

echo
if [[ "$FAILS" -eq 0 ]]; then
  green "All tests passed ($TESTS total)."
  exit 0
else
  red "$FAILS / $TESTS tests failed."
  exit 1
fi
