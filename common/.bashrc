# Unlike my usual shell tendency to write for some common denominator
# of shells, this file is called ".bashrc" so I have no compunctions
# about using Bash-ishms here.


######################################################################
### Loading up other people's ideas of what should be in my bashrc.

# Homebrew's installation of bash-completion gets angry if it can't
# find "brew" in the path.  We'll clean up PATH later.
PATH=$PATH:/usr/local/bin:/opt/homebrew/bin

# Use bash_completion.  I think this was born from Ubuntu's
# /etc/skel/.bashrc, which (I guess) suggested /etc/bash_completion as
# the thing to source.
#
# MacPorts has bash_completion in /opt/local/etc.  Homebrew has
# /usr/local/etc/profile.d/bash_completion.sh.
#
# Fedora sources bash_completion for us, and something bad happens
# when you re-source it, so we avoid that.
if [[ -z "$BASH_COMPLETION" || ! -r "$BASH_COMPLETION" ]]; then
	for script in /etc/bash_completion \
	              /opt/local/etc/bash_completion \
	              /usr/local/etc/profile.d/bash_completion.sh \
	              /opt/homebrew/etc/profile.d/bash_completion.sh
	do
		if [ -r "$script" ]; then
			. "$script"
			break
		fi
	done
	unset script
fi

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
	local where
	where=$(which "$1" 2>&1)
	[ -x "$where" ]
	return $?
}  # is_available


######################################################################
### PATH

# Note use of && here to short-circuit calling uname -i when the
# directories aren't found, which is useful on OS X where uname -i
# creates an error (and where neither of the lib64 directories exist).
if [[ (-e /lib64 || -d /usr/lib64) && "$(uname -i)" = "x86_64" ]]; then
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
# Homebrew.  Put the ARM Mac path first, /usr/local/bin second since that may
# or may not be the one we intend.
PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
# MacPorts
PATH=/opt/local/bin:/opt/local/sbin:$PATH
# Local directories, for OpenBSD ports and Homebrew.
PATH=/usr/local/bin:/usr/local/sbin:$PATH
# The various places ccache might get installed.
PATH=/usr/local/opt/ccache/libexec:$PATH
PATH=/opt/local/libexec/ccache:$PATH
PATH=/usr/$LIB/ccache:$PATH
PATH=$HOME/ccache-bin:$PATH
# rbenv.  We add its shims directory ourselves, because if we don't,
# subsequent invocations of the shell will find the shims directory
# pushed to the end of the PATH, and then rbenv won't try and put it
# nearer the front of the path, and then shit breaks because ruby gets
# found in /usr/bin before ~/.rbenv/shims/ruby.  I should probably
# file a bug in rbenv?
PATH=$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH
# Maybe Ruby gems installed with --user-install.  In my experience,
# this always yields a directory, even if that directory doesn't
# exist.
if command -v ruby >/dev/null; then
	PATH=$(ruby -r rubygems -e 'puts Gem.user_dir')/bin:$PATH
fi
# npm packages installed in my home directory.
PATH=$HOME/.npm-packages/bin:$PATH
# Go
if command -v go >/dev/null; then
	PATH=$(go env GOPATH)/bin:$PATH
fi
# Rust
PATH=$HOME/.cargo/bin:$PATH
# Rancher Desktop
PATH=$HOME/.rd/bin:$PATH
# ~/bin used to be where I put all my own scripts (see below), so it
# gets put near first still. (Remove this once I've gotten rid of the
# machines using ~/bin.)
PATH=$HOME/bin:$PATH
# I think ~/.local/bin is the XDG standard directory nowadays.  This
# one always goes first because this (now) where I keep my own
# programs.
PATH=$HOME/.local/bin:$PATH
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
	if [ -n "${new_PATH##*:$dir:*}" ] && [ -d "$dir" ]; then
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
	if ! temp_file=$(mktemp -t vipath.XXXXXXXX) || [ ! -O "$temp_file" ]; then
		echo "couldn't create temp file $temp_file" >&2
		return 1
	fi
	echo "$PATH" | tr ':' '\n' > "$temp_file"
	if "$EDITOR" "$temp_file"; then
		local new_path
		while read -r line; do
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

# macOS Catalina stopped putting a blank entry in MANPATH somehow, so
# I stopped getting all the system man pages from the developer tools.
# Check for this and put it back in if necessary.
found_blank_MANPATH=0
saved_IFS=$IFS
IFS=:
set -f
for dir in ${MANPATH:-}; do
	if [ -z "$dir" ]; then
		found_blank_MANPATH=1
		break
	fi
done
unset dir
set +f
IFS=$saved_IFS
if [ $found_blank_MANPATH -eq 0 ]; then
	MANPATH=$MANPATH:
	export MANPATH
fi
unset found_blank_MANPATH

HISTFILESIZE=1000000
HISTSIZE=1000000
HISTCONTROL=ignoredups:ignorespace
# Show date and time with history lines.
HISTTIMEFORMAT='%F %T '
# Append to history.
shopt -s histappend
# Append after every command.  I'm hoping this prevents the last shell
# to exit from obliterating the history of every other shell I have
# open.
PROMPT_COMMAND="${PROMPT_COMMAND:+${PROMPT_COMMAND}; }history -a"

# check the window size after each command and, if necessary, update
# the values of LINES and COLUMNS.  (Stolen from Ubuntu; RH/FC does
# this in /etc/bashrc.)
shopt -s checkwinsize

# I like this on so I can use negative globbing.
shopt -s extglob

export TZ=America/Chicago
export LC_COLLATE=C

if [ -d "$HOME/Maildir/" ]
then
	MAIL=$HOME/Maildir/
elif [ -d "$HOME/Mailbox" ]
then
	MAIL=$HOME/Mailbox
fi

# Holy shit do I hate accidentally hitting M-n/M-p and then wondering
# where the fuck my command went.  (These are non-incremental search
# forward/backward in history, by default.)
bind -r '\en'
bind -r '\ep'

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
sudo() {
	local status old_umask
	old_umask=$(umask)
	# 0022 is the old default sudo umask, AFAIK.
	umask 0022
	command sudo "$@"
	status=$?
	umask "$old_umask"
	return $status
}

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
	eval "$("$dircolors" --sh "$HOME/.dircolors")"
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
	if [ "${LESS:=-RF}" != "-RF" ]; then
		LESS="${LESS%% -RF} -RF"
	fi
	export LESS

	if command -v bat >/dev/null; then
		export LESSOPEN="|batfilter %s"
	elif is_available lesspipe; then
		# Ubuntu /etc/skel/.bashrc sets up lesspipe like this.
		# RH/Fedora uses lesspipe.sh, so this should be OK.
		eval "$(lesspipe)"
	fi

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

if REAL_RIPGREP=$(type -P rg); then
	rg() {
		if [[ -t 0 && -t 1 ]]; then
			"$REAL_RIPGREP" -p "$@" | "${PAGER:-less}"
		else
			"$REAL_RIPGREP" "$@"
		fi
	}

	ag() {
		echo "use rg, ag has broken .gitignore support" >&2
		return 1
	}
fi

RIPGREP_CONFIG_PATH=$HOME/.rgrc
export RIPGREP_CONFIG_PATH

if ! command -v telnet >/dev/null; then
	for telnet_subst in ncat socat nc; do
		if command -v "$telnet_subst" >/dev/null; then
			case "$telnet_subst" in
				ncat | nc)
					alias telnet="$telnet_subst -v"
					;;

				socat)
					telnet() {
						if [ $# -lt 1 ] || [ $# -gt 2 ]; then
							echo "telnet is really socat function," \
							     "host and port only please"
							return 1
						fi
						local host=$1
						local port
						if [ $# -eq 2 ]; then
							port=$2
						else
							port=23
						fi
						socat -d -d "tcp:$host:$port" stdio
					}
					;;
			esac
			break
		fi
	done
fi

export YDIFF_OPTIONS='-t 4 --wrap'

if [ "$(uname -s)" = Darwin ]; then
	# Poor macOS users have no ssh-askpass.  I hacked one up in
	# Python.  Use it if SSH_ASKPASS isn't set and if the binary is
	# present.
	if [ -z "$SSH_ASKPASS" ]; then
		SSH_ASKPASS=$HOME/.local/bin/ssh-askpass
		if [ -x "$SSH_ASKPASS" ]; then
			export SSH_ASKPASS
		else
			unset SSH_ASKPASS
		fi
	fi
	# Guys, guys, you'll never believe this, but SSH_ASKPASS won't be
	# used unless DISPLAY is set.
	if [ -z "$DISPLAY" ]; then
		DISPLAY=openssh_please_use_askpass
		export DISPLAY
	fi
fi

if ! command -v idea &>/dev/null; then
	idea() {
		open -na "IntelliJ IDEA.app" --args "$@"
	}
fi


######################################################################
### Python

# Strip empty string and "." out of PYTHONPATH, put there by my
# company's bashrc (see near top).  Remove any duplicates while I'm at
# it.  (Awk trick suggested by several places, but
# http://unix.stackexchange.com/a/14896 was the one that hooked me.
# Maybe I should change my PATH stuff up top to do this instead of
# manipulating IFS.)
PYTHONPATH=$(echo -n "$PYTHONPATH" |
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
	local activate
	activate=$WORKON_HOME/$1/bin/activate
	if [ ! -r "$activate" ]; then
		# Maybe it's a path to a virtual environment.
		activate=$1/bin/activate
		if [ ! -r "$activate" ]; then
			echo "can't find virtualenv '$1'" >&2
			return 1
		fi
	fi
	if [ "$(type -t deactivate)" = "function" ]; then
		deactivate
	fi
	. "$activate"
}

# https://github.com/pypa/pipx/issues/1212
export PIPX_HOME=$HOME/.local/share/pipx


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
### .NET Core (oh god I'm so sorry)

export DOTNET_CLI_TELEMETRY_OPTOUT=1


######################################################################
### Colima

if command -v colima >/dev/null; then
	source <(colima completion bash)
	cnerdctl() {
		# Colima's own alias (colima nerctl install) adds --profile
		# default, but I don't know if/why I need to do that.
		colima nerdctl -- "$@"
	}
fi


######################################################################
### Various completion

command -v gopass >/dev/null && source <(gopass completion bash)
command -v limactl >/dev/null && source <(limactl completion bash)
command -v docker >/dev/null && source <(docker completion bash)


######################################################################
### Aids for changing directories

# This is all below RVM, which modifies the cd command.

# fasd (https://github.com/clvv/fasd) has problems with long argument
# lists.  Let's try zoxide (https://github.com/ajeetdsouza/zoxide) I
# guess?  Other possibilities include
# https://github.com/skywind3000/z.lua and good ol'
# https://github.com/rupa/z.

if command -v zoxide >/dev/null; then
	eval "$(zoxide init bash)"
	# Make it more like good ol' fasd.
	alias zz=zi
elif command -v fasd >/dev/null; then
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
### fzf

# MacPorts drops fzf's Bash completion setup into the bash-completion
# load-on-demand directory, but I don't think that's right: when
# installed this way I think the script never gets executed
# unless/until you actually try to run "fzf ...", at which point the
# completion script gets loaded.  Instead, we will always immediately
# load fzf's Bash completion script.
#
# Naturally, MacPorts and Homebrew drop the files for fzf in totally
# different places, so we have to support both.
fzf_scripts=()
if [ -n "${PS1:-}" ]; then
	if [ -r /opt/local/share/fzf/shell/key-bindings.bash ]; then
		# MacPorts
		fzf_scripts=(/opt/local/share/fzf/shell/{completion,key-bindings}.bash)
	elif [ -r /usr/local/opt/fzf/shell ]; then
		# Intel Homebrew
		fzf_scripts=(/usr/local/opt/fzf/shell/{completion,key-bindings}.bash)
	elif [ -r /opt/homebrew/opt/fzf/shell ]; then
		# ARM Homebrew
		fzf_scripts=(/opt/homebrew/opt/fzf/shell/{completion,key-bindings}.bash)
	else
		fzf_scripts=()
	fi
fi
if (( ${#fzf_scripts[@]} )); then
	# Here is a generic wrapper around an existing completion function
	# to choose from its resulting candidates with fzf.  See below
	# usage as with Git.

	# Call with completion function as first argument, followed by the
	# rest of the arguments the completion function should be given.
	__fzf_completion_function_wrapper () {
		local func
		func=$1
		shift 1
		"$func" "$@" || return
		# If the completion function did not fill out COMPREPLY (an
		# array) with candidates, then skip running fzf.
		if [ "${#COMPREPLY[@]}" -gt 0 ]; then
			# _fzf_complete is the documented fzf method for making a
			# custom completion command.
			#
			# If you look at the code for _fzf_complete, you'll see
			# why we have to make it think its trigger is the empty
			# string, but the simple explanation is that, if
			# _fzf_complete doesn't see its trigger at the end of the
			# line, it tries to pass through control to other
			# completion providers.  Setting it to the empty string is
			# an ugly hack, but now it will always find its (empty)
			# trigger at the end of the line.
			FZF_COMPLETION_TRIGGER='' _fzf_complete -- "$@" < <(
				# This prints each unique element of COMPREPLY, one
				# per line.
				printf "%s\n" "${COMPREPLY[@]}" | sort -u
			)
		fi
	}

	# Call with the name of a command that already has completion set
	# up, in order to wrap its completion with fzf.
	__fzf_wrap_existing_completion () {
		local command=$1
		local i cmd_func_idx complete_func='' wrapper_name
		local -a complete_cmd
		# Read the current completion specification into complete_cmd.
		# This is the recommended way to do this, according to
		# ShellCheck.
		if ! IFS=" " read -r -a complete_cmd \
		     <<< "$(complete -p "$command" | head -1)"; then
			echo "No completion defined for $command" >&2
			return 1
		fi
		# This iterates over all the indexes in complete_cmd.
		for i in "${!complete_cmd[@]}"; do
			# Look for the -F option to Bash's "complete" builtin and
			# snag the function named after that option.
			if [ "${complete_cmd[$i]}" = "-F" ]; then
				cmd_func_idx=$((i + 1))
				complete_func=${complete_cmd[$cmd_func_idx]}
				break
			fi
		done
		if [ -z "$complete_func" ]; then
			echo "Cannot determine completion function for $command" >&2
			return 2
		fi
		if [ "$(printf %q "$complete_func")" != "$complete_func" ]; then
			echo "Name of completion function \"$complete_func\" looks" >&2
			echo "dangerous, bailing" >&2
			return 3
		fi
		wrapper_name=__fzf_wrapped__$complete_func
		eval "$wrapper_name () {
			__fzf_completion_function_wrapper '$complete_func' \"\$@\"
		}"
		# Re-execute the original completion command, but now with our
		# function named instead of the original completion function.
		complete_cmd[$cmd_func_idx]=$wrapper_name
		"${complete_cmd[@]}"
	}

	# MacPorts requires me to load the Git completions with
	# _completion_loader.  Homebrew loads them up front, but
	# _completion_loader still exists.  Furthermore, MacPorts wants
	# you to load completions out of "git" but Homebrew has them in
	# "git-completion".  _completion_loader will, in fact, *clobber an
	# existing completion* for X if you try "_completion_loader X"
	# without having a
	# /usr/local/share/bash-completion/completions/X.bash.  So we have
	# to do this hacky stuff.
	if type _completion_loader &> /dev/null; then
		regexp='__git_wrap__git'
		if [[ ! $(complete -p git 2>/dev/null) =~ $regexp ]]; then
			# Force immediate loading of Git completion functions, so
			# __fzf_wrap_existing_completion can wrap them.
			_completion_loader git
		fi
		unset regexp
	fi

	__fzf_wrap_existing_completion git
	__fzf_wrap_existing_completion gitk

	for script in "${fzf_scripts[@]}"; do
		source "$script"
	done
	unset script fzf_scripts

	# This is the normal way to add fzf completion to a command in
	# Bash, per fzf's docs.  Without this, "**" will not trigger fzf
	# path completion.  This must be done after
	# __fzf_wrap_existing_completion.  Note that our magic above to
	# make fzf the default for all commands does not apply to git (and
	# gitk) since they have specific completion functions.  (complete
	# -o bashdefault apparently doesn't mean "call the default
	# completion function if this one fails", much to my surprise.)
	_fzf_setup_completion path git

	# Put back my C-t, move FZF to M-i instead.  Emacs user checking in.
	bind '"\C-t": transpose-chars'
	# (This actually breaks in Bash < v4.)
	bind -m emacs-standard -x '"\ei": fzf-file-widget'

	FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border --bind alt-p:toggle-preview"
	export FZF_DEFAULT_OPTS
	FZF_COMPLETION_TRIGGER='xx'
	FZF_CTRL_R_OPTS="${FZF_CTRL_R_OPTS:-} --preview='echo {}' --preview-window=up:3:wrap"

	if command -v fd >/dev/null; then
		# fd might be faster than find.
		FZF_DEFAULT_COMMAND='fd -H --color=always'
		FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS --ansi"
		FZF_CTRL_T_COMMAND=$FZF_DEFAULT_COMMAND
	fi

	# Complete all commands with "**"?  I don't know why this isn't
	# the default for Bash.  Thinking complete -D might be too new?
	# Or else this is going to break horribly in ways I can't predict.
	complete -D -F _fzf_path_completion -o default -o bashdefault

	# Enable fzf completion with the first word on the line.  Need to
	# use our own function to change $1 from "_InitialWorD_" (magic
	# value in Bash, I *think*) to "", in order to avoid recursion
	# between fzf's functions and bash-completions' functions.
	_fzf_complete_initial_word () {
		shift 1
		_fzf_path_completion "" "$@"
	}

	complete -I -F _fzf_complete_initial_word -o default -o bashdefault
fi

######################################################################
### Other cute commands

vimkill () {
	local temp_file
	if ! temp_file=$(mktemp -t vimkillXXXXXXXXXX); then
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
### Fancy prompt

# This comes at/near the bottom to make sure it can put itself first
# in PROMPT_COMMAND.  Without doing that, we can't see the value of $?.

vterm_printf() {
	if [ -n "$TMUX" ]; then
		# Tell tmux to pass the escape sequences through
		# (Source: http://permalink.gmane.org/gmane.comp.terminal-emulators.tmux.user/1324)
		printf "\ePtmux;\e\e]%s\007\e\\" "$1"
	elif [ "${TERM%%-*}" = "screen" ]; then
		# GNU screen (screen, screen-256color, screen-256color-bce)
		printf "\eP\e]%s\007\e\\" "$1"
	else
		printf "\e]%s\e\\" "$1"
	fi
}

# Bash manual documents testing PS1 as a valid way to know if you're
# in an interactive shell.
if [[ "$PS1" ]]; then
	_term_sgr() {
		local fg_bg color
		while [ $# -gt 0 ]; do
			case "$1" in
				reset)
					tput sgr0
					shift 1
					;;

				rgb)
					[ $# -ge 3 ] || return 1
					case "$2" in
						fg) fg_bg=38 ;;
						bg) fg_bg=48 ;;
						*) return 1 ;;
					esac
					color=${3#\#}
					printf '\e[%d;2;%d;%d;%dm' $fg_bg \
						   "0x${color:0:2}" "0x${color:2:2}" "0x${color:4:2}"
					shift 3
					;;

				fg|bg)
					[ $# -ge 2 ] || return 1
					case "$1" in
						fg) fg_bg=setaf ;;
						bg) fg_bg=setab ;;
					esac
					case "$2" in
						black   ) color=0 ;;
						red     ) color=1 ;;
						green   ) color=2 ;;
						yellow  ) color=3 ;;
						blue    ) color=4 ;;
						magenta ) color=5 ;;
						cyan    ) color=6 ;;
						white   ) color=7 ;;
						default ) color=9 ;;
						*) return 1 ;;
					esac
					tput $fg_bg $color
					shift 2;
					;;

				bold)
					tput bold
					shift 1
					;;

				*)
					return 1
					;;
			esac
		done
	}

	_fancy_prompt_green=$(_term_sgr rgb bg 006600 fg white bold)
	_fancy_prompt_red=$(_term_sgr rgb bg b30000 fg white bold)
	_fancy_prompt_reset=$(_term_sgr reset)

	_VIRTUAL_ENV_PS1_REGEXP='^\(([^\)]+)\) (.*)(\\[wW].*)$'
	# Apparently Bash 4.3 started expanding REPL in ${PARM/PAT/REPL}
	# expressions ("setopt -s compat42").  Thanks to #bash for this
	# workaround.
	_A_TILDE=\~
	_prompt_command() {
		if [ $? -eq 0 ]; then
			_fancy_prompt_color=$_fancy_prompt_green
		else
			_fancy_prompt_color=$_fancy_prompt_red
		fi

		# Terminating with BEL rather than ESC \.  The latter is
		# proper standard, the former is supported by more
		# (particularly GNU Screen).
		printf '\033]0;%s@%s:%s\007' \
		       "$USER" "${HOSTNAME%%.*}" "${PWD/#$HOME/$_A_TILDE}"
		if [[ $PS1 =~ $_VIRTUAL_ENV_PS1_REGEXP && $VIRTUAL_ENV ]]; then
			PS1="${BASH_REMATCH[2]}(${BASH_REMATCH[1]}) ${BASH_REMATCH[3]}"
		fi
	}
	PROMPT_COMMAND="_prompt_command${PROMPT_COMMAND:+; ${PROMPT_COMMAND}}"
	PS1='\[${_fancy_prompt_color}\]⮕ \u@\h \[${_fancy_prompt_reset}\] \W \$ '
	if [ "$INSIDE_EMACS" = vterm ]; then
		vterm_prompt_end(){
			vterm_printf "51;A$(whoami)@$(hostname):$(pwd)"
		}
		PS1=$PS1'\[$(vterm_prompt_end)\]'
		PROMPT_COMMAND="${PROMPT_COMMAND:+${PROMPT_COMMAND}; }
		                echo -ne \"\033]0;${HOSTNAME%%.*}:${PWD}\007\""
	fi
fi


######################################################################
### direnv

# I bet this needs to be after the prompt stuff, since I bet this is
# going to hook in via the prompt.

if command -v direnv &>/dev/null; then
	eval "$(direnv hook bash)"
fi


######################################################################
### Cleanup

unset is_available


######################################################################
### Machine-local settings

[ -f "$HOME/.bashrc.local" ] && source "$HOME/.bashrc.local"
