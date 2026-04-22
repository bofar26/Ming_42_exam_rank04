NAME := microshell
CC := cc
CFLAGS := -Wall -Wextra -Werror
SRCS := microshell.c
OBJS := $(SRCS:.c=.o)

.PHONY: all clean fclean re test

all: $(NAME)

$(NAME): $(OBJS)
	$(CC) $(CFLAGS) $(OBJS) -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

test: $(NAME)
	@bash tests/test.sh

clean:
	rm -f $(OBJS)

fclean: clean
	rm -f $(NAME)
	rm -rf .test_tmp

re: fclean all
