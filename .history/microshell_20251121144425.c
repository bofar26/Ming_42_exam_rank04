/* ************************************************************************** */
/*                                                                            */
/*                            microshell.c (单文件版)                          */
/*   满足题目全部要求：                                                       */
/*   - 支持 | 和 ;                                                            */
/*   - 仅实现内建 cd（只接受一个路径参数）                                    */
/*   - 不构造 PATH；execve 直接用 argv[0]                                     */
/*   - 任何除 execve/chdir 外的系统调用出错 => "error: fatal\n" 并退出         */
/*   - execve 失败 => "error: cannot execute <path>\n"                        */
/*   - 管道采用滚动 prev_in，避免 FD 爆炸                                     */
/*                                                                            */
/* ************************************************************************** */

#include <unistd.h>     /* write, close, fork, execve, dup2, pipe, chdir */
#include <stdlib.h>     /* exit */
#include <string.h>     /* strcmp, strncmp */
#include <sys/wait.h>   /* waitpid */

/* ---------- 小工具 ---------- */

static size_t ms_strlen(const char *s) {
    size_t n = 0;
    while (s && s[n]) n++;
    return n;
}

static void ms_putstr_fd(const char *s, int fd) {
    if (s) (void)!write(fd, s, ms_strlen(s));
}

static void fatal(void) {
    ms_putstr_fd("error: fatal\n", 2);
    exit(1);
}

/* ---------- 执行一个命令段 argv[l..r-1] ---------- */
/* in_fd: 作为该段 stdin 的 fd（-1 表示不改）         */
/* out_fd: 作为该段 stdout 的 fd（-1 表示不改）        */
/* *last_pid: 若 fork 了子进程，返回它的 pid            */
/* 返回值：是否创建了需要等待的子进程（0/1）           */
static int run_segment(char **argv, int l, int r,
                       int in_fd, int out_fd,
                       char **envp, int *last_pid)
{
    argv[r] = NULL; /* 截断本段 */

    /* 内建 cd：只接受一个参数 */
    if (strcmp(argv[l], "cd") == 0) {
        if (r - l != 2) {
            ms_putstr_fd("error: cd: bad arguments\n", 2);
            return 0;
        }
        if (chdir(argv[l + 1]) == -1) {
            ms_putstr_fd("error: cd: cannot change directory to ", 2);
            ms_putstr_fd(argv[l + 1], 2);
            ms_putstr_fd("\n", 2);
        }
        return 0; /* 内建不 fork */
    }

    pid_t pid = fork();
    if (pid < 0) fatal();

    if (pid == 0) {
        /* 子进程：接好重定向后 execve */
        if (in_fd != -1 && dup2(in_fd, 0) == -1) fatal();
        if (out_fd != -1 && dup2(out_fd, 1) == -1) fatal();
        if (in_fd != -1 && close(in_fd) == -1) fatal();
        if (out_fd != -1 && close(out_fd) == -1) fatal();

        execve(argv[l], &argv[l], envp);
        ms_putstr_fd("error: cannot execute ", 2);
        ms_putstr_fd(argv[l], 2);
        ms_putstr_fd("\n", 2);
        exit(1);
    }

    *last_pid = (int)pid;
    return 1;
}

/* 批量等待（被 ; 或结尾 切分的一批） */
static void wait_all(pid_t *pids, int n) {
    for (int i = 0; i < n; i++) {
        if (waitpid(pids[i], NULL, 0) == -1)
            fatal();
    }
}

int main(int argc, char **argv, char **envp)
{
    (void)argc;

    int i = 1;              /* 遍历 argv 的游标（跳过程序名） */
    int start = 1;          /* 当前段起点 */
    int prev_in = -1;       /* 上一条管道的读端，作为下一段的 stdin */
    pid_t pids[4096];       /* 收集当前批次子进程 pid */
    int pcnt = 0;

    while (argv[i]) {
        /* 遇到 | 或 ; 就处理 [start, i) 这段命令 */
        if (strcmp(argv[i], "|") == 0 || strcmp(argv[i], ";") == 0) {
            if (i - start > 0) {
                int is_pipe = (strcmp(argv[i], "|") == 0);
                int pipefd[2] = {-1, -1};
                int out_fd = -1;
                int last_pid = -1;

                if (is_pipe) {
                    if (pipe(pipefd) == -1) fatal();
                    out_fd = pipefd[1]; /* 子进程 stdout -> 写端 */
                }

                /* 执行本段 */
                int need_wait = run_segment(argv, start, i, prev_in, out_fd, envp, &last_pid);

                /* 父进程：整理 FD，滚动 prev_in */
                if (is_pipe) {
                    if (close(pipefd[1]) == -1) fatal();  /* 关闭写端 */
                    if (prev_in != -1 && close(prev_in) == -1) fatal();
                    prev_in = pipefd[0];                  /* 下一段的 stdin */
                } else {
                    if (prev_in != -1 && close(prev_in) == -1) fatal();
                    prev_in = -1;
                }

                if (need_wait) {
                    if (pcnt >= (int)(sizeof(pids)/sizeof(pids[0]))) fatal();
                    pids[pcnt++] = (pid_t)last_pid;
                }
            }

            /* 分号：结束一个“批次”，等待之 */
            if (strcmp(argv[i], ";") == 0) {
                wait_all(pids, pcnt);
                pcnt = 0;
            }

            start = i + 1;
        }
        i++;
    }

    /* 处理末尾段（没有跟分隔符） */
    if (i - start > 0) {
        int last_pid = -1;
        int need_wait = run_segment(argv, start, i, prev_in, -1, envp, &last_pid);
        if (prev_in != -1 && close(prev_in) == -1) fatal();
        prev_in = -1;
        if (need_wait) {
            if (pcnt >= (int)(sizeof(pids)/sizeof(pids[0]))) fatal();
            pids[pcnt++] = (pid_t)last_pid;
        }
    }

    /* 等待最后一批 */
    wait_all(pids, pcnt);
    return 0;
}
