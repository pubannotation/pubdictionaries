require 'mkmf'
$CFLAGS='-I../../include'
$LDFLAGS="-lstdc++"

have_library("iconv", "libiconv_open")
create_makefile('simstring')

