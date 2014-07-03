$pdf_previewer = $pdf_update_command = "open %O %S";
# Uncomment this if you want latexmk -pvc to re-run the "open" command
# above whenever your file changes.
#$pdf_update_method = 4;

$pdf_mode = 1;

# Don't stop on errors and use lualatex because it's exciting (and
# needed for things such as fontspec).
$pdflatex = "lualatex -interaction=nonstopmode";

# Taken from http://tex.stackexchange.com/a/44316/1680
add_cus_dep('glo', 'gls', 0, 'run_makeglossaries');
add_cus_dep('acn', 'acr', 0, 'run_makeglossaries');

sub run_makeglossaries {
  if ( $silent ) {
    system "makeglossaries -q '$_[0]'";
  }
  else {
    system "makeglossaries '$_[0]'";
  };
}

push @generated_exts, 'glo', 'gls', 'glg';
push @generated_exts, 'acn', 'acr', 'alg';
$clean_ext .= ' %R.ist %R.xdy';
