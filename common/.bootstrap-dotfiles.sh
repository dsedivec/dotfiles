#!/bin/sh
set -ex || exit 1
git clone git@github.com:dsedivec/dotfiles.git ~/dotfiles
# -p is probably bad because it may change permissions on ~ such that
# sshd will no longer accept your authorized_keys.  Hence we're not
# just using -a.
#
# -o and -g shouldn't be necessary either, for that matter.
rsync -rltDv ~/dotfiles/ ~/
rm -rf ~/dotfiles
echo '*' >> ~/.git/info/exclude
install -d ~/.vim/bundle
cd ~/.vim/bundle
git clone git://github.com/gmarik/vundle.git
