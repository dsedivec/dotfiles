#!/usr/bin/env bash

[ -f ~/.bashrc ] && . ~/.bashrc

if [ "x$SSH_AGENT_PID" = "x" -a "x$SSH_AUTH_SOCK" = "x" ] \
   && [ -e "$HOME/.ssh/id_dsa" -o -e "$HOME/.ssh/id_rsa" ]
then
	eval "`ssh-agent -s`"
	SSH_AGENT_PPID=$$
fi
