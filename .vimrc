call pathogen#infect()

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

" I like filetype guessing and syntax highlighting now.
filetype plugin indent on
syntax on

" Mail settings
aug new_mail
au User all set textwidth=70 noet ts=8 syntax=mail spell
au User all set formatoptions+=tn2l
au User all set formatlistpat=^\\s*\\(\\d\\+[\\]:.)}]\\\|[*-]\\)\\s\\+
au User all syntax on
aug END
au BufRead mutt[-A-Za-z0-9]* do new_mail User all

let c_space_errors=1
