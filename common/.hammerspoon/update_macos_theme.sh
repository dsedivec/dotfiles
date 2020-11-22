#!/usr/bin/env bash

set -u

result=0

dark_mode=$(osascript -e 'tell application "System Events" to get the dark mode of appearance preferences') \
	|| { echo "Can't get dark mode status" >&2; exit 1; }

case "$dark_mode" in
	true)
		iterm_color_preset="Dark Background"
		textual_style="Simplified Dark"
		;;

	false)
		iterm_color_preset="Light Background"
		textual_style="Simplified Light"
		;;

	*)
		echo "Unknown response for dark mode: $dark_mode" >&2
		exit 1
		;;
esac

export PATH=$HOME/bin:/opt/local/bin:$PATH
ITERM2_PYTHON_VERSION=3.8.6
TEXTUAL_AUTO_STYLE_NAME="Simplified Auto"
TEXTUAL_APP=$HOME/Applications/Textual.app

ITERM2_PYTHONS=$HOME/Library/ApplicationSupport/iTerm2/iterm2env/versions
TEXTUAL_APP_STYLES=$TEXTUAL_APP/Contents/Resources/Bundled\ Styles
TEXTUAL_USER_STYLES=$HOME/Library/Group\ Containers/com.codeux.apps.textual/Library/Application\ Support/Textual/Styles

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
		iterm2_python=$ITERM2_PYTHONS/$ITERM2_PYTHON_VERSION/bin/python
		"$iterm2_python" "$PWD/set_iterm2_color_theme.py" \
		                 "$iterm_color_preset" || result=1
	else
		result=1
	fi
	unset ITERM2_COOKIE
fi

# Textual
textual_src_style=$TEXTUAL_APP_STYLES/$textual_style
textual_dst_style=$TEXTUAL_USER_STYLES/$TEXTUAL_AUTO_STYLE_NAME
install -d "$TEXTUAL_USER_STYLES" || result=1
rsync -av "$textual_src_style/" "$textual_dst_style/" || result=1

exit $result
