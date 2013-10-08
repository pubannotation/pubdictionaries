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

cd simstring-1.0
./configure
cd swig/ruby
./prepare.sh --swig
cp ../../../extconf.rb .
ruby extconf.rb
make

