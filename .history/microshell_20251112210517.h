#ifndef MICROSHELL_H
# define MICROSHELL_H

# include <unistd.h>
# include <stdlib.h>

size_t  ft_strlen(const char *s);
int     ft_strcmp(const char *a, const char *b);   /* 仅用于比较字面量/argv */
void    putstr_fd(const char *s, int fd);
void    fatal(void);

#endif
