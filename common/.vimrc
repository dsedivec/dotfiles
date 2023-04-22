" Notes:
" Leader is \

" vim-plug
" Upgrade vim-plug: :PlugUpgrade
" Upgrade plugins: :PlugUpdate
call plug#begin('~/.vim/plugged')

" Plug-ins
Plug 'tpope/vim-sensible'
Plug 'scrooloose/nerdcommenter'
Plug 'easymotion/vim-easymotion'
" Lets you kill a buffer without killing its window.
" Try :BW (instead of :bw)
" Possible alternative: https://github.com/moll/vim-bbye
Plug 'qpkorr/vim-bufkill'
Plug 'jlanzarotta/bufexplorer'
" Bsgrep!
Plug 'jeetsukumaran/vim-buffersaurus'
" :Ag
Plug 'rking/ag.vim'

if version >= 702
	Plug 'jamessan/vim-gnupg'
	let g:GPGUseAgent=1
	let g:GPGPreferSymmetric=1
endif

" Recommended by
" http://www.vimninjas.com/2012/09/03/5-plugins-you-should-put-in-your-vimrc/

" Surround things with matched pairs
" https://github.com/tpope/vim-surround/
Plug 'tpope/vim-surround'
" Find files.  Pure Vim alternative to Command-T, but try Command-T if this is
" too slow, perhaps.
" https://github.com/ctrlpvim/ctrlp.vim
Plug 'ctrlpvim/ctrlp.vim'
let g:ctrlp_extensions = ['buffertag']
" Syntax checking for lots of languages.
" https://github.com/scrooloose/syntastic
Plug 'scrooloose/syntastic'

" Recommended by https://news.ycombinator.com/item?id=4470283

" Nice status line.  Note: probably only works with Vim >= 7.2.
" Seems harmless on 7.0 though.
"Plug 'Lokaltog/vim-powerline'
" vim-powerline going away in favor of powerline which requires
" me to install it with Python and pip?  WTF?  Lokaltog
" refers me to vim-airline.
Plug 'vim-airline/vim-airline'
" Powerline settings
set laststatus=2   " Always show the statusline
set encoding=utf-8 " Necessary to show Unicode glyphs
set t_Co=256 " Explicitly tell Vim that the terminal supports 256 colors

"Plug 'wincent/command-t', {
"\   'do': 'cd ruby/command-t/ext/command-t && ruby extconf.rb && make'
"\ }

Plug 'majutsushi/tagbar'
nmap <F8> :TagbarToggle<CR>

call plug#end()
" Note that vim-plug does "filetype plug indent on" and "syntax enable".

"colorscheme koehler
colorscheme delek
if has('macunix')
	if system('defaults read -g AppleInterfaceStyle 2>&1') == "Dark"
		set background=dark
	else
		set background=light
	endif
endif

set nohlsearch
" Both work together
set ignorecase smartcase
" Necessary?
set nocompatible
" Allow switching away from a modified buffer
set hidden
set printoptions=paper:letter

" Make bracketed paste work on tmux within iTerm.  Really this just enables it
" for anything that vaguely looks like "screen".  Good luck.
if &term =~ "screen"
	let &t_BE = "\e[?2004h"
	let &t_BD = "\e[?2004l"
	exec "set t_PS=\e[200~"
	exec "set t_PE=\e[201~"
endif

" Mail settings
aug new_mail
au User all set textwidth=70 noet ts=8 syntax=mail spell
au User all set formatoptions+=tn2l
au User all set formatlistpat=^\\s*\\(\\d\\+[\\]:.)}]\\\|[*-]\\)\\s\\+
au User all syntax on
aug END
au BufRead mutt[-A-Za-z0-9]* do new_mail User all

au FileType gitcommit setlocal spell

au FileType sh setlocal ts=4 sw=4

au FileType python setlocal et sw=4 ts=4 ai si sm

au FileType yaml setlocal et sw=2

" Fix for editing crontab with vim under OS X.
" http://vim.wikia.com/wiki/Editing_crontab
au BufEnter /private/tmp/crontab.* setlocal backupcopy=yes

" gopass editing without temp files
" Pattern based on actions/edit.go and utils/tempfile/file.go.
" autocmd suggested by docs/setup.md.
" Additional random settings from https://vi.stackexchange.com/q/6177
au BufNewFile,BufRead */gopass-edit*/secret setlocal noswapfile nobackup noundofile noshelltemp nowritebackup

let c_space_errors=1
