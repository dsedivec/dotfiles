# Unlike my usual shell tendency to write for some common denominator
# of shells, this file is called ".bashrc" so I have no compunctions
# about using Bash-ishms here.


######################################################################
### Loading up other people's ideas of what should be in my bashrc.

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
if [ -z "$BASH_COMPLETION" -o ! -r "$BASH_COMPLETION" ]; then
	for dir in /etc /opt/local/etc; do
		script=$dir/bash_completion
		if [ -r "$script" ]; then
			. "$script"
			break
		fi
	done
	unset dir script
fi

# SSC bashrc.  This is probably purposely above almost everything else
# so that I can override any of its settings that I don't care for.
ssc_bashrc=~/git/system/dotfiles/developer-bashrc
[ -r "$ssc_bashrc" ] && . "$ssc_bashrc"
unset ssc_bashrc
# That loaded a lot of aliases that I don't need, let's just clear out
# aliases entirely.
unalias -a
# Our Java 1.4 really screws with my Clojure development
unset JAVA_HOME

# Source global definitions.  Note that Debian/Ubuntu may have
# /etc/bash.bashrc, but if they do then their version of Bash is
# configured with a compile-time option to execute that file
# automatically, so no need to consider it here.
#
# OS X has an /etc/profile that executes /etc/bashrc--naughty!
if [ -r /etc/bashrc ] && [ "$(uname -s)" != "Darwin" ]; then
	# RH, FC
	. /etc/bashrc
fi


######################################################################
### Useful functions for this bashrc.  May be unset on our way out.

# Tests if a program is available.
is_available () {
	local where=$(which "$1" 2>&1)
	[ -x "$where" ]
	return $?
}  # is_available


######################################################################
### PATH

# Some SSC scripts use this I _think_.  I also use it here building up
# my PATH.
POSTGRESQL=$HOME/pgsql
export POSTGRESQL

# Note use of && here to short-circuit calling uname -i when the
# directories aren't found, which is useful on OS X where uname -i
# creates an error (and where neither of the lib64 directories exist).
if [ -e /lib64 -o -d /usr/lib64 ] && [ "$(uname -i)" = "x86_64" ]; then
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
# rbenv.  We add its shims directory ourselves, because if we don't,
# subsequent invocations of the shell will find the shims directory
# pushed to the end of the PATH, and then rbenv won't try and put it
# nearer the front of the path, and then shit breaks because ruby gets
# found in /usr/bin before ~/.rbenv/shims/ruby.  I should probably
# file a bug in rbenv?
PATH=$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH
# npm packages installed in my home directory.
PATH=$HOME/.npm-packages/bin:$PATH
# Cabal (Haskell; I like ShellCheck)
PATH=$HOME/.cabal/bin:$PATH
# Finally, ~/bin always goes first.
PATH=$HOME/bin:$PATH
# At the end we want to make sure we get the usual bin directories,
# including sbins.  We also add on /usr/games for OpenBSD.
PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/games

# Done with this now.
unset LIB

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


######################################################################
### General settings

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


HISTFILESIZE=1000000
HISTSIZE=1000000
HISTCONTROL=ignoredups:ignorespace
# Show date and time with history lines.
HISTTIMEFORMAT='%F %T '
# Append to history.
shopt -s histappend

# check the window size after each command and, if necessary, update
# the values of LINES and COLUMNS.  (Stolen from Ubuntu; RH/FC does
# this in /etc/bashrc.)
shopt -s checkwinsize

# I like this on so I can use negative globbing.
shopt -s extglob

export TZ=America/Chicago
export LC_COLLATE=C

if [ -d $HOME/Maildir/ ]
then
	MAIL=$HOME/Maildir/
elif [ -d $HOME/Mailbox ]
then
	MAIL=$HOME/Mailbox
fi

# On OS X 10.5[.3, at least] things other than Terminal.app seem to be
# getting COMMAND_MODE=legacy.  This changes what get_compat returns,
# which several OS X tools use.  For example, with
# COMMAND_MODE=legacy, "crontab -r" prompts to ask if you want to
# remove your crontab.
if [ "$(uname -s)" = "Darwin" ]; then
	release=$(uname -r)
	major=${release%%.*}
	# Only apply to Darwin >= 9, which should correspond to Mac OS X
	# >= 10.5.  (Is this needed on OS X 10.4?  I never had a
	# problem on 10.4 that I could attribute to this setting.)
	if [ "$major" -ge 9 ]; then
		COMMAND_MODE=unix2003
		export COMMAND_MODE
	fi
	unset release major minor
fi

umask 007
ulimit -c unlimited


######################################################################
### Setup for other programs

# Newer sudo changes umask behavior.  This restores the old behavior
# and keeps people at work from yelling at me when I touch critical
# files under sudo and accidentally tighten their permissions.
if [ $? -eq 0 ]; then
	sudo() {
		local status old_umask=$(umask)
		# 0022 is the old default sudo umask, AFAIK.
		umask 0022
		command sudo "$@"
		status=$?
		umask "$old_umask"
		return $status
	}
fi

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
[ "$(type -t ls)" = "alias" ] && unalias ls
# LS_FLAGS is used un-quoted to get word splitting.
ls() { command "$LS" $LS_FLAGS "$@"; }

# Enable color support in GNU ls.  dircolors taken from Ubuntu
# /etc/skel/.bashrc.
if [ "$TERM" != "dumb" ] && is_available "$dircolors"; then
	eval $("$dircolors" --sh "$HOME/.dircolors")
	LS_FLAGS="$LS_FLAGS --color=auto"
fi

# Done with this variable.
unset dircolors

if is_available less
then
	PAGER=less
	export PAGER

	# -R makes colors work in ag when it uses less as a pager in OS
	# X/iTerm 2.  -F makes less exit when all the output fits on a
	# single screen, which is nice when doing something like "git log
	# --oneline -1".  Just make sure to turn off alternate screen
	# clearing (e.g. "Disable save/restore alternate screen" in
	# iTerm2) otherwise you'll do "git log --oneline -1" and then
	# you'll see no output until you think to try something like
	# "git log --oneline -1 | cat".
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

# I wish there was such thing as ~/.agrc.
alias ag="ag --pager=less --smart-case"

# Open ag results in Vim or Emacs.  Vim requires ag.vim from
# https://github.com/rking/ag.vim, Emacs requires ag.el from
# https://github.com/Wilfred/ag.el as well as (my:focus-emacs) from
# https://github.com/dsedivec/dot-emacs-d/blob/master/lisp/my/general-config.el.
vag() {
	local -a quoted_args=()
	for arg in "$@"; do
		quoted_args+=("$(printf %q "$arg")")
	done
	vim -c ":Ag! ${quoted_args[*]}" -c ":only"
}

eag() {
	local quoted_arg quoted_pwd
	local -a quoted_args=()
	for arg in "$@"; do
		quoted_arg=$(printf %q "$arg")
		# Great, you've quoted for the shell.  Now quote for Emacs.
		quoted_arg=${quoted_arg//\\/\\\\}
		quoted_arg=${quoted_arg//\"/\\\"}
		quoted_args+=("$quoted_arg")
	done
	quoted_pwd=$(printf %q "$PWD")
	quoted_pwd=${quoted_pwd//\\/\\\\}
	quoted_pwd=${quoted_pwd//\"/\\\"}
	emacsclient --eval "
		(progn
		  (compilation-start \"cd $quoted_pwd; ag --smart-case --color --color-match '30;43' --column --nogroup ${quoted_args[*]}\" 'ag-mode)
		  (pop-to-buffer \"*ag*\")
		  (my:focus-emacs))
	"
}

######################################################################
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
	if [ -n "$STY" ]; then
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
		if [ -z "${opt##[rxdRD]}" ]; then
			reattach=1
			if [ -z "${OPTARG##-[a-zA-Z]}" ]; then
				OPTIND=$(($OPTIND - 1))
			else
				pattern="-S $OPTARG"
			fi
		elif [ "$opt" = ":" -a -z "${OPTARG##[rxdRD]}" ]; then
			# Reattach option with no option argument.
			reattach=1
		elif [ "$opt" = "S" ]; then
			create=1
			session="$OPTARG"
		elif [ "$opt" = ":" -a "$OPTARG" = "S" ]; then
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
	if [ -e "$SSH_AUTH_SOCK" -a \( ! -e "$sock" -o -L "$sock" \) ]; then
		ln -sf "$SSH_AUTH_SOCK" "$sock"
	fi

	# It isn't necessary to specify SSH_AUTH_SOCK when doing a
	# reattach, only when creating a new session.
	SSH_AUTH_SOCK=$sock screen $set_name "$@"
}


######################################################################
### Python

# Strip empty string and "." out of PYTHONPATH, put there by my
# company's bashrc (see near top).  Remove any duplicates while I'm at
# it.  (Awk trick suggested by several places, but
# http://unix.stackexchange.com/a/14896 was the one that hooked me.
# Maybe I should change my PATH stuff up top to do this instead of
# manipulating IFS.)
PYTHONPATH=$(echo -n $PYTHONPATH |
	awk -v RS=: -v ORS=: '!p[$0]++ && $0 !~ /^\.?$/')
# Damn that trailing ORS.
PYTHONPATH=${PYTHONPATH%:}

# "workon" makes it easy to switch virtualenvs.  I know there are some
# packages that do exactly what I'm doing below, and more on top of
# it.  I just don't feel like installing them on all the systems I use
# when the below works pretty darn well.

export WORKON_HOME=${WORKON_HOME:-$HOME/.vpy}

workon() {
	if [ $# -ne 1 ]; then
		echo "usage: $FUNCNAME <virtualenv name>" >&2
		return 1
	fi
	local activate=$WORKON_HOME/$1/bin/activate
	if [ -r "$activate" ]; then
		if [ "$(type -t deactivate)" = "function" ]; then
			deactivate
		fi
		. "$activate"
	else
		echo "can't find virtualenv '$1'" >&2
		return 1
	fi
}

######################################################################
### Node.js/npm

npm_man_dir=$HOME/.npm-packages/share/man
if [ -d "$npm_man_dir" ]; then
	# Starting this variable with a colon seems to mean "append the
	# following directories to usual search path," at least on CentOS
	# 5 and OS X 10.11.  This is usually the desired behavior.
	# However, it might be more portable to run $(manpath) here
	# instead of depending on that behavior, which I'm not sure is
	# documented, at least not on OS X.
	MANPATH=$MANPATH:$npm_man_dir
fi
unset npm_man_dir

######################################################################
### RVM

if [ -s "$HOME/.rvm/scripts/rvm" ]; then
	. "$HOME/.rvm/scripts/rvm"
fi

######################################################################
### rbenv

if [ -r ~/.rbenv/bin/rbenv ]; then
	eval "$(rbenv init -)"
fi

######################################################################
### Aids for changing directories

# This is all below RVM, which modifies the cd command.

# fasd: https://github.com/clvv/fasd
if which fasd &> /dev/null; then
	eval "$(fasd --init auto)"
fi

# I like cd to print the full path of where I just changed to.  I
# don't see a built-in for this in bash.
#
# We take care to possibly wrap a cd which is already a function, such
# as the function RVM (above) installs.  That's why this is so far
# down in the file.
if [ "$(type -t cd)" = "function" ]; then
	real_cd=_cd_before_printing_pwd
	# Recipe for copying a function (in lieu of renaming) from
	# http://stackoverflow.com/questions/1203583/how-do-i-rename-a-bash-function
	eval "$(echo 'function' $real_cd; declare -f cd | tail -n +2)"
else
	real_cd="builtin cd"
fi

# eval'ing the function so I can unset real_cd afterwards.
# Redirecting cd into /dev/null because "cd -" already prints PWD.
# (CDPATH may also cause it to print a directory, I think.  I'm using
# CDPATH.)
eval '
cd () {
	'"$real_cd"' "$@" >/dev/null && echo "$PWD"
}
'

unset real_cd


######################################################################
### Other cute commands

vimkill () {
	local temp_file
	temp_file=$(mktemp -t vimkillXXXXXXXXXX)
	if [ $? -ne 0 ]; then
		echo "mktemp failed" >&2
		return 1
	fi
	if ! pgrep -fl "$@" > "$temp_file"; then
		rm "$temp_file"
		echo "no matching processes found" >&2
		return 1
	fi
	cat >> "$temp_file" <<-EOF
		# Delete lines you don't want
		# Feel free to add additional PIDs, one per line
		# Lines that don't start with a number will be ignored
		# Exit non-zero (Vim: :cquit) to abort or just delete all lines
		EOF
	local status=1
	if "${EDITOR:-vi}" "$temp_file"; then
		pids=$(awk -v ORS=' ' '/^[0-9]+/{print $1}' "$temp_file")
		if [ -n "$pids" ]; then
			echo "Killing $pids"
			kill $pids
			status=$?
		else
			echo "no PIDs to kill" >&2
		fi
	else
		echo "editor exited non-zero, nothing killed" >&2
	fi
	rm "$temp_file"
	return $status
}


######################################################################
### Cleanup

unset is_available
