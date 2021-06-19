#!/usr/bin/env bash

[ -f ~/.bashrc ] && . ~/.bashrc

if [[ -z "$SSH_AGENT_PID" && -z "$SSH_AUTH_SOCK" ]]; then
	eval "$(ssh-agent -s)"
fi
