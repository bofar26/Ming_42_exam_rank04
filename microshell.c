#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>

void    ft_putstr_fd2(char *str, char *arg)
{
    while (*str)
        write(2, str++, 1);
    if (arg)
        while (*arg)
            write(2, arg++, 1);
    write(2, "\n", 1);
}

void    fatal(void)
{
    write(2, "error: fatal\n", 13);
    exit(1);
}

void    ft_execute(char **argv, int i, int tmp_fd, char **env)
{
    argv[i] = NULL;
    if (dup2(tmp_fd, STDIN_FILENO) < 0)
        fatal();
    close(tmp_fd);
    execve(argv[0], argv, env);
    ft_putstr_fd2("error: cannot execute ", argv[0]);
    exit(1);
}

int     main(int argc, char **argv, char **env)
{
    int     i;
    int     fd[2];
    int     tmp_fd;
    int     last_status;
    pid_t   last_pid;
    pid_t   pid;
    int     status;

    (void)argc;
    last_status = 0;
    last_pid = 0;
    tmp_fd = dup(STDIN_FILENO);
    if (tmp_fd < 0)
        fatal();
    argv++;
    while (*argv)
    {
        i = 0;
        while (argv[i] && strcmp(argv[i], ";") && strcmp(argv[i], "|"))
            i++;
        if (argv[0] && !strcmp(argv[0], "cd"))
        {
            if (i != 2)
                ft_putstr_fd2("error: cd: bad arguments", NULL);
            else if (chdir(argv[1]) != 0)
                ft_putstr_fd2("error: cd: cannot change directory to ", argv[1]);
        }
        else if (i != 0 && (!argv[i] || !strcmp(argv[i], ";")))
        {
            pid = fork();
            if (pid < 0)
                fatal();
            if (pid == 0)
                ft_execute(argv, i, tmp_fd, env);
            else
            {
                close(tmp_fd);
                last_pid = pid;
                while ((pid = waitpid(-1, &status, 0)) != -1)
                    if (pid == last_pid && WIFEXITED(status))
                        last_status = WEXITSTATUS(status);
                tmp_fd = dup(STDIN_FILENO);
                if (tmp_fd < 0)
                    fatal();
            }
        }
        else if (i != 0 && !strcmp(argv[i], "|"))
        {
            if (pipe(fd) < 0)
                fatal();
            pid = fork();
            if (pid < 0)
                fatal();
            if (pid == 0)
            {
                if (dup2(fd[1], STDOUT_FILENO) < 0)
                    fatal();
                close(fd[0]);
                close(fd[1]);
                ft_execute(argv, i, tmp_fd, env);
            }
            else
            {
                close(fd[1]);
                close(tmp_fd);
                tmp_fd = fd[0];
            }
        }
        if (!argv[i])
            break;
        argv = &argv[i + 1];
    }
    close(tmp_fd);
    return (last_status);
}
