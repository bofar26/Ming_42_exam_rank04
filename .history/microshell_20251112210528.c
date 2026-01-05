#include "microshell.h"
#include <sys/wait.h>
#include <string.h> /* 只为题目允许的 strcmp/strncmp，亦自备 ft_strcmp */
#include <errno.h>

/* --- tiny utils --- */

size_t ft_strlen(const char *s) {
    size_t n = 0;
    while (s && s[n]) n++;
    return n;
}
int ft_strcmp(const char *a, const char *b) {
    size_t i = 0;
    if (!a || !b) return (a != b);
    while (a[i] && b[i] && a[i] == b[i]) i++;
    return ((unsigned char)a[i] - (unsigned char)b[i]);
}
void putstr_fd(const char *s, int fd) {
    if (s) (void)!write(fd, s, ft_strlen(s));
}
void fatal(void) {
    putstr_fd("error: fatal\n", 2);
    exit(1);
}

/* --- exec helpers --- */

static void child_exec(char **argv, char **envp, int in_fd, int out_fd) {
    if (in_fd != -1 && dup2(in_fd, 0) == -1) fatal();
    if (out_fd != -1 && dup2(out_fd, 1) == -1) fatal();
    if (in_fd != -1 && close(in_fd) == -1) fatal();
    if (out_fd != -1 && close(out_fd) == -1) fatal();
    execve(argv[0], argv, envp);
    putstr_fd("error: cannot execute ", 2);
    putstr_fd(argv[0], 2);
    putstr_fd("\n", 2);
    exit(1);
}

static int run_segment(char **argv, int l, int r, int in_fd, int out_fd, char **envp, int *last_pid) {
    /* argv[l..r-1] 是一个命令；调用者已保证非空 */
    argv[r] = NULL;
    if (ft_strcmp(argv[l], "cd") == 0) {
        /* 题目保证 cd 不会被管道前后紧贴；但仍按规范检查参数个数与 chdir 结果 */
        if ((r - l) != 2) {
            putstr_fd("error: cd: bad arguments\n", 2);
            return 0;
        }
        if (chdir(argv[l + 1]) == -1) {
            putstr_fd("error: cd: cannot change directory to ", 2);
            putstr_fd(argv[l + 1], 2);
            putstr_fd("\n", 2);
        }
        return 0; /* 内建不 fork，不进入等待队列 */
    } else {
        pid_t pid = fork();
        if (pid < 0) fatal();
        if (pid == 0) child_exec(&argv[l], envp, in_fd, out_fd);
        *last_pid = (int)pid;
        return 1; /* 需要等待 */
    }
}

/* 等待当前批次（被 ; 或输入结束 终止的批次）的所有子进程 */
static void wait_all(pid_t *pids, int n) {
    int i;
    for (i = 0; i < n; i++) {
        if (waitpid(pids[i], NULL, 0) == -1) fatal();
    }
}

int main(int argc, char **argv, char **envp) {
    (void)argc;
    int i = 1;
    int start = 1;
    int prev_in = -1;        /* 上一个管道的读端（供本段作为 stdin） */
    pid_t pids[4096];        /* 简单数组收集本批子进程 PID（足够大） */
    int pcnt = 0;

    while (argv[i]) {
        /* 找到一个段（被 | 或 ; 或结尾分隔） */
        if (ft_strcmp(argv[i], "|") == 0 || ft_strcmp(argv[i], ";") == 0) {
            /* 处理 start..i-1 */
            if (i - start > 0) {
                int need_wait = 0;
                int pipefd[2] = {-1, -1};
                int out_fd = -1;
                int last_pid = -1;

                int is_pipe = (ft_strcmp(argv[i], "|") == 0);
                if (is_pipe) {
                    if (pipe(pipefd) == -1) fatal();
                    out_fd = pipefd[1];
                }

                need_wait = run_segment(argv, start, i, prev_in, out_fd, envp, &last_pid);
                if (is_pipe) {
                    /* 父进程关闭写端，保存读端给下一段当 stdin */
                    if (close(pipefd[1]) == -1) fatal();
                    if (prev_in != -1 && close(prev_in) == -1) fatal();
                    prev_in = pipefd[0];
                } else {
                    /* 分号：关闭任何遗留的 prev_in */
                    if (prev_in != -1 && close(prev_in) == -1) fatal();
                    prev_in = -1;
                }

                if (need_wait) {
                    if (pcnt >= (int)(sizeof(pids)/sizeof(pids[0]))) fatal();
                    pids[pcnt++] = (pid_t)last_pid;
                }
            }
            if (ft_strcmp(argv[i], ";") == 0) {
                /* 批次结束，等待所有子进程 */
                wait_all(pids, pcnt);
                pcnt = 0;
            }
            start = i + 1;
        }
        i++;
    }

    /* 末尾段（若有） */
    if (i - start > 0) {
        int need_wait = 0;
        int last_pid = -1;
        need_wait = run_segment(argv, start, i, prev_in, -1, envp, &last_pid);
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
