#!/bin/sh
set -e || exit 1
git clone git@github.com:dsedivec/dotfiles.git ~/dotfiles
rsync -av ~/dotfiles/ ~/
rm -rf ~/dotfiles
echo '*' >> ~/.git/info/exclude
