" Must turn off filetype before loading Vundle, apparently.
filetype off
set runtimepath+=~/.vim/bundle/vundle/
call vundle#rc()

" Bundles to install, Vundle must be listed here.
Bundle 'gmarik/vundle'
Bundle 'scrooloose/nerdcommenter'

" I like filetype guessing and syntax highlighting now.
" (Vundle is now loaded so can turn filetype on.)
filetype plugin indent on
syntax on

"colorscheme koehler
colorscheme delek

set nohlsearch
set viminfo=
" This is backwards-compatible (to Vim 5) backspace
" setting.  In Vim 6 I believe it's equivalent to
"    set backspace=start,eol,indent
set backspace=2
set ruler
set printoptions=paper:letter

" Mail settings
aug new_mail
au User all set textwidth=70 noet ts=8 syntax=mail spell
au User all set formatoptions+=tn2l
au User all set formatlistpat=^\\s*\\(\\d\\+[\\]:.)}]\\\|[*-]\\)\\s\\+
au User all syntax on
aug END
au BufRead mutt[-A-Za-z0-9]* do new_mail User all

let c_space_errors=1
