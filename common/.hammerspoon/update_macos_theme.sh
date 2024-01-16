#!/usr/bin/env bash

set -u

result=0

dark_mode=$(osascript -e 'tell application "System Events" to get the dark mode of appearance preferences') \
	|| { echo "Can't get dark mode status" >&2; exit 1; }

case "$dark_mode" in
	true)
		iterm_color_preset="Dark Background"
		;;

	false)
		iterm_color_preset="Light Background"
		;;

	*)
		echo "Unknown response for dark mode: $dark_mode" >&2
		exit 1
		;;
esac

export PATH=$HOME/.local/bin:/opt/local/bin:$PATH

ITERM2_PYTHONS=$HOME/Library/Application\ Support/iTerm2/iterm2env/versions

my_dir=$(dirname "$0")
cd "$my_dir" || exit 1

# Emacs
emacsclient -a true \
            --eval "(run-at-time 0 nil #'my:set-theme-for-macos-system-theme)" \
	|| result=1

# iTerm 2
if pgrep iTerm2; then
	if ITERM2_COOKIE=$(osascript -e 'tell application "iTerm2" to request cookie'); then
		export ITERM2_COOKIE
		for dir in "$ITERM2_PYTHONS"/3.10*; do
			iterm2_python=$dir/bin/python
		done
		"$iterm2_python" "$PWD/set_iterm2_color_theme.py" \
		                 "$iterm_color_preset" || result=1
	else
		result=1
	fi
	unset ITERM2_COOKIE
fi

exit $result
