# For now, I don't feel bad about using bash-isms here.

# Source global definitions
if [ -r /etc/bashrc ]; then
	# RH, FC
	. /etc/bashrc
elif [ -r /etc/bash.bashrc ]; then
	# Debian
	. /etc/bash.bashrc
fi

# Use bash_completion.  I think this was stolen from Ubuntu's
# /etc/skel/.bashrc.
#
# MacPorts has bash_completion in /opt/local/etc.
#
# Fedora sources bash_completion for us, and something bad happens
# when you re-source it, so we avoid that.
#
# This is loaded before the SSC developer's .bashrc (below) so it can
# pick up that we have the Git completion stuff.
if [ "x$BASH_COMPLETION" = "x" -o ! -r "$BASH_COMPLETION" ]; then
	for dir in /etc /opt/local/etc; do
		script=$dir/bash_completion
		if [ -r "$script" ]; then
			. "$script"
			break
		fi
	done
	unset dir script
fi

# SSC bashrc.  This is probably purposely above everything else so
# that I can override any of its settings that I don't care for.
ssc_bashrc=~/git/system/dotfiles/developer-bashrc
[ -r "$ssc_bashrc" ] && . "$ssc_bashrc"
unset ssc_bashrc

# Other SSC variables (which may be used further on in this .bashrc!).
# (I don't actually know if this is used _outside_ of this .bashrc.)
POSTGRESQL=$HOME/pgsql
export POSTGRESQL

# Tests if a program is available.
is_available () {
	local where=$(which "$1" 2>&1)
	[ -x "$where" ]
	return $?
}  # is_available

if [ -e /lib64 -o -d /usr/lib64 ] && [ "x`uname -i`" = "xx86_64" ]; then
	LIB="lib64"
else
	LIB="lib"
fi

# We add directories we want first and last in the PATH.  We'll remove
# duplicates next.
#
# Unfortunately we have to add stuff on to the front of the path in
# reverse order.
#
# MacPorts
PATH=/opt/local/bin:/opt/local/sbin:$PATH
# Local directories, for OpenBSD ports and SSC /usr/local/bin/python.
PATH=/usr/local/bin:/usr/local/sbin:$PATH
# SSC PostgreSQL install.
PATH=$POSTGRESQL/bin:$PATH
# The various places ccache might get installed.
PATH=$HOME/ccache-bin:/usr/$LIB/ccache:/opt/local/libexec/ccache:$PATH
# Finally, ~/bin always goes first.
PATH=$HOME/bin:$PATH
# At the end we want to make sure we get the usual bin directories,
# including sbins.  We also add on /usr/games for OpenBSD.
PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/games

# Now we're going to remove duplicates and non-existent directories
# from the PATH.
#
# new_PATH must always start and end with a colon so we can do
# duplicate checking with globs.  We'll take out the empty PATH
# components at the end.
new_PATH=:
saved_IFS=$IFS
IFS=:
for dir in $PATH; do
	if [ -n "${new_PATH##*:$dir:*}" -a -d "$dir" ]; then
		new_PATH=$new_PATH$dir:
	fi
done
IFS=$saved_IFS
# Remove colons from front and back.
PATH=${new_PATH#:}
PATH=${PATH%:}
unset new_PATH saved_IFS dir

# Here's a useful command to edit your path in e.g. vi:
vipath() {
	local temp_file
	# This mktemp invocation works on both OS X and Linux, though it
	# doesn't do what you expect in OS X.
	temp_file=$(mktemp -t vipath.XXXXXXXX)
	if [ $? -ne 0 -o ! -O "$temp_file" ]; then
		echo "couldn't create temp file $temp_file" >&2
		return 1
	fi
	echo "$PATH" | tr ':' '\n' > "$temp_file"
	if "$EDITOR" "$temp_file"; then
		local new_path
		while read line; do
			# Strip whitespace.
			line=$(echo "$line" | sed 's/^[[:space:]]*//g; s/[[:space:]]*$//g')
			if [ -n "$line" ]; then
				new_path="$new_path:$line"
			fi
		done < "$temp_file"
		new_path=${new_path#:}
		if [ -z "$new_path" ]; then
			echo "refusing to set empty PATH" >&2
			return 1
		fi
		PATH=$new_path
	else
		echo "$EDITOR exited non-zero, not setting PATH" >&2
		return 1
	fi
}

# Copied from FC5 /etc/bashrc.
# are we an interactive shell?
if [ "$PS1" ]; then
	case $TERM in
		xterm*)
			PROMPT_COMMAND='echo -ne "\033]0;${USER}@${HOSTNAME%%.*}:${PWD/#$HOME/~}"; echo -ne "\007"'
			;;

		screen)
			PROMPT_COMMAND='echo -ne "\033_${USER}@${HOSTNAME%%.*}:${PWD/#$HOME/~}"; echo -ne "\033\\"'
			;;
	esac
	PS1='[\u@\h \W]\$ '
	export PS1
fi

# Stolen from Ubuntu: don't put duplicate lines in the history. See
# bash(1) for more options
export HISTCONTROL=ignoredups

# check the window size after each command and, if necessary, update
# the values of LINES and COLUMNS.  (Stolen from Ubuntu; RH/FC does
# this in /etc/bashrc.)
shopt -s checkwinsize

# I like this on so I can use negative globbing.
shopt -s extglob

umask 007
ulimit -c unlimited

# Newer sudo changes umask behavior.  This restores the old behavior
# and keeps people at work from yelling at me.
SUDO=$(which sudo)
if [ $? -eq 0 ]; then
	sudo() {
		local status old_umask=$(umask)
		# 0022 is the old default sudo umask, AFAIK.
		umask 0022
		"$SUDO" "$@"
		status=$?
		umask "$old_umask"
		return $status
	}
fi

TZ=America/Chicago
export TZ

LC_COLLATE=C
export LC_COLLATE

# Which ls to use.  MacPorts GNU ls is "gls" and that'll give us all
# the options and colors we're used to.
if is_available gls; then
	LS=gls dircolors=gdircolors
else
	LS=ls dircolors=dircolors
fi

# Accumulate flags for ls invocation here.
LS_FLAGS="-F"
export LS_FLAGS

# You can't define a function called ls if there is an alias for ls.
# Fedora's /etc/profile.d/colorls.sh does this automatically.
[ "x$(type -t ls)" = "xalias" ] && unalias ls
# LS_FLAGS is used un-quoted to get word splitting.
ls() { command "$LS" $LS_FLAGS "$@"; }

# Enable color support in GNU ls.  dircolors taken from Ubuntu
# /etc/skel/.bashrc.
if [ "$TERM" != "dumb" ] && is_available "$dircolors"; then
	eval `"$dircolors" --sh "$HOME/.dircolors"`
	LS_FLAGS="$LS_FLAGS --color=auto"
fi

# Don't need this anymore.
unset dircolors

if [ -d $HOME/Maildir/ ]
then
	MAIL=$HOME/Maildir/
elif [ -d $HOME/Mailbox ]
then
	MAIL=$HOME/Mailbox
fi

if is_available less
then
	PAGER=less
	export PAGER

	# Make colors work in less (under OS X; works under Linux, don't
	# know why).
	LESS="$LESS -RF"
	export LESS

	# Ubuntu /etc/skel/.bashrc sets up lesspipe like this.  RH/Fedora
	# uses lesspipe.sh, so this should be OK.
	is_available lesspipe && eval "$(lesspipe)"
fi

# We use full paths here because git (MacPorts' 1.5.6.4 or so) is
# breaking otherwise.
if is_available vim
then
	EDITOR=$(which vim)
	alias vi=vim
else
	EDITOR=$(which vi)
fi
VISUAL="$EDITOR"
export VISUAL EDITOR

# Emacs on OS X.
emacs_app=$HOME/Applications/Emacs.app/Contents/MacOS/Emacs
if [ -x "$emacs_app" ]; then
	export EMACS=$emacs_app

	emacsclient=$HOME/Library/Emacs/bin/emacsclient
	if [ -x "$emacsclient" ]; then
		export EMACSCLIENT=$emacsclient
	fi
	unset emacsclient
fi
unset emacs_app

### SSH agent forwarding under a long running screen

# We need to know where our Screen FIFOs are kept so we can check for
# a duplicate session name.
[ -d ~/.screens ] || { mkdir ~/.screens; chmod 700 ~/.screens; }
SCREENDIR=~/.screens
export SCREENDIR

# Think of it as a parameterized constant.
get_screen_auth_sock() { echo ~/.ssh/agent-screen-"$1"; }

# Clean up dead sockets.
find ~/.ssh -maxdepth 1 -path "$(get_screen_auth_sock '*')" -type l \
	| while read link
do
	[ -e "$link" ] || rm -f $link
done

sshscreen() {
	if [ "x$STY" != "x" ]; then
		echo "don't use sshscreen from inside screen" >&2
		return 1
	fi

	if ! type -P gawk >/dev/null; then
		echo "sshscreen requires gawk (not found)" >&2
		return 1
	fi

	local OPTIND=1 opt pattern session num_sessions sock
	local create=0 reattach=0 set_name=""
	while getopts ":r:x:d:R:D:S:" opt; do
		if [ "x${opt##[rxdRD]}" = "x" ]; then
			reattach=1
			if [ "x${OPTARG##-[a-zA-Z]}" = "x" ]; then
				OPTIND=$(($OPTIND - 1))
			else
				pattern="-S $OPTARG"
			fi
		elif [ "x$opt" = "x:" -a "x${OPTARG##[rxdRD]}" = "x" ]; then
			# Reattach option with no option argument.
			reattach=1
		elif [ "x$opt" = "xS" ]; then
			create=1
			session="$OPTARG"
		elif [ "x$opt" = "x:" -a "x$OPTARG" = "xS" ]; then
			echo "-S requires an argument" >&2
			return 1
		fi
	done

	if [ $create -eq 1 -a $reattach -eq 1 ]; then
		echo "sshscreen can't handle -S and a reattach option as well" >&2
		return 1
	elif [ $create -eq 0 -a $reattach -eq 0 ]; then
		# I assume we're creating a new session.  I attempt to mimic
		# the default Screen session name here.  I fear the
		# portability of "hostname -s".  (I mean, really, I fear the
		# portability of a whole lot of this.)
		create=1
		session="$(tty | sed 's!^/dev/!!; s/[^a-zA-Z0-9]/-/g').$(hostname -s)"
		set_name="-S $session"
	elif [ $reattach -eq 1 ]; then
		# Three argument form of match() is a GNU extension.
		session=$(screen $pattern -ls \
			      | gawk '/[ \t]+[0-9]+/{match($0, /[0-9]+\.([^ \t]+)/, m);
	                                     print m[1]; c = c + 1} END{exit(c)}')
		num_sessions=$?
		if [ $num_sessions -le 0 ]; then
			echo "no matching sessions found" >&2
			return 1
		elif [ $num_sessions -gt 1 ]; then
			echo "more than one matching session, please be more specific" >&2
			screen $pattern -ls
			return 1
		fi
	fi

	if [ $create -eq 1 ]; then
		find $SCREENDIR -print | sed 's/^[0-9]*\.//' | fgrep -q -- "$session"
		if [ $? -eq 0 ]; then
			# We can't have a duplicate session name, because they
			# would share the same SSH agent socket.  Note that by
			# "session name" I mean the portion of the name listed by
			# "screen -ls" with the leading "<pid>." removed.
			echo "session name '$session' not unique," \
				"please specify a different one with -S" >&2
			return 1
		fi
	fi

	sock=$(get_screen_auth_sock "$session")
	if [ -e "$SSH_AUTH_SOCK" ] && [ ! -e "$sock" -o -L "$sock" ]; then
		ln -sf "$SSH_AUTH_SOCK" "$sock"
	fi

	# It isn't necessary to specify SSH_AUTH_SOCK when doing a
	# reattach, only when creating a new session.
	SSH_AUTH_SOCK=$sock screen $set_name "$@"
}

# On OS X 10.5[.3, at least] things other than Terminal.app seem to be
# getting COMMAND_MODE=legacy.  This changes what get_compat returns,
# which several OS X tools use.  For example, with
# COMMAND_MODE=legacy, "crontab -r" prompts to ask if you want to
# remove your crontab.
if [ "x$(uname -s)" = "xDarwin" ]; then
	release=$(uname -r)
	major=${release%%.*}
	minor=${release#*.}
	minor=${minor%%.*}
	# Only apply to Darwin >= 9, which should correspond to Mac OS X
	# >= 10.5.  (Is this needed on OS X 10.4?  I never had a
	# problem on 10.4 that I could attribute to this setting.)
	if [ "$major" -ge 9 ]; then
		COMMAND_MODE=unix2003
		export COMMAND_MODE
	fi
	unset release major minor
fi

unset is_available
unset LIB

# RVM
if [ -s "$HOME/.rvm/scripts/rvm" ]; then
	. "$HOME/.rvm/scripts/rvm"
	PATH=$PATH:$HOME/.rvm/bin
fi

# z: https://github.com/rupa/z
[ -r "$HOME/.z.sh" ] && . "$HOME/.z.sh"
