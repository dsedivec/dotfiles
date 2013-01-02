#!/bin/sh
set -ex || exit 1
git clone git@github.com:dsedivec/dotfiles.git ~/dotfiles
rsync -av ~/dotfiles/ ~/
rm -rf ~/dotfiles
echo '*' >> ~/.git/info/exclude
install -d ~/.vim/bundle
cd ~/.vim/bundle
git clone git://github.com/gmarik/vundle.git
