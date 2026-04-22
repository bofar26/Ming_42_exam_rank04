#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>

void	fatal()
{
	write(2, "error: fatal\n", 13);
	exit(1);
}

void	ft_putstr_fd2(char *str, char *arg)
{
	while (*str)
		write(2, str++, 1);
	if (arg)
		while (*arg)
			write(2, arg++, 1);
	write(2, "\n", 1);
}

void	ft_execute(char **argv, int i, int tmp_pd, char **env)
{
	argv[i] = NULL;
	if (dup2(tmp_pd, STDIN_FILENO) < 0)
		fatal();
	close(tmp_pd);
	execve(argv[0], argv, env);
	ft_putstr_fd2("error: cannot execute ", argv[0]);
	exit(1);
}

int	main(int argc, char **argv, char **env)
{
	int	i;
	int	tmp_pd;
	int	status;
	int	last_status;
	int	fd[2];
	pid_t	pid;
	pid_t	last_pid;

	(void)argc;
	last_status = 0;
	last_pid = 0;
	tmp_pd = dup(STDIN_FILENO);
	if (tmp_pd < 0)
		fatal();
	argv ++;
	while (*argv)
	{
		i = 0;
		while (argv[i] && strcmp(argv[i], ";") && strcmp(argv[i], "|"))
			i ++;
		if (i != 0 && argv[0] && !strcmp(argv[0], "cd"))
		{
			if (i != 2)
				ft_putstr_fd2("error: cd: bad arguments", NULL);
			else if (chdir(argv[1]) < 0)
				ft_putstr_fd2("error: cd: cannot change directory to ", argv[1]);
		}
		else if (i != 0 && (!argv[i] || !strcmp(argv[i], ";")))
		{
			pid = fork();
			if (pid < 0)
				fatal();
			if (pid == 0)
				ft_execute(argv, i, tmp_pd, env);
			else
			{
				close(tmp_pd);
				last_pid = pid;
				while ((pid = waitpid(-1, &status, 0)) != -1)
					if (pid == last_pid && WIFEXITED(status))
						last_status = WEXITSTATUS(status);
				tmp_pd = dup(STDIN_FILENO);
				if (tmp_pd < 0)
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
				close(fd[1]);
				close(fd[0]);
				ft_execute(argv, i, tmp_pd, env);
			}
			else
			{
				close(fd[1]);
				close(tmp_pd);
				tmp_pd = fd[0];
			}
		}
		if (!argv[i])
			break ;
		argv = &argv[i + 1];
	}
	close(tmp_pd);
	return (last_status);
}
