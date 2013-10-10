#!/bin/bash

#
#   Creating a ruby extension of SimString may cause a problem in OS X. If
# you see errors somthing like
#  
#   "dyld: lazy symbol binding failed: Symbol not found: libiconvopen ..."
#
# , then add one line, "have_liary("iconv", "libiconv_open")", in the 
# simstring-1.0/swig/ruby/extconf.rb file before the "create_make" command."
#

# Solution for the issue #9
#   - https://github.com/chokkan/simstring/issues/9
#
OLD_MMF_POSIX_H=simstring-1.0/include/simstring/memory_mapped_file_posix.h.old
if [ ! -f $OLD_MMF_POSIX ]; then
  mv simstring-1.0/include/simstring/memory_mapped_file_posix.h $OLD_MMF_POSIX_H
  cp memory_mapped_file_posix.h ./simstring-1.0/include/simstring/memory_mapped_file_posix.h
fi

# Solution for header not found (simstring.h in export.cpp)
#
OLD_EXPORT_CPP=simstring-1.0/swig/export.cpp.old
if [ ! -f $OLD_EXPORT_CPP ]; then
  mv simstring-1.0/swig/export.cpp $OLD_EXPORT_CPP
  cp export.cpp simstring-1.0/swig/export.cpp
fi

cd simstring-1.0
./configure
cd swig/ruby
./prepare.sh --swig

# Solution for the issue #12
#   - A libiconv problem in OS-X
OLD_EXTCONF=extconf.rb.old
if [ ! -f $OLD_EXTCONF ]; then
  mv extconf.rb extconf.rb.old
  cp ../../../extconf.rb .
fi

ruby extconf.rb
make


