#!/bin/bash

cd simstring-1.0
./configure
cd swig/ruby
#swig -c++ -ruby export.i
#./prepare.sh --swig
./prepare.sh
ruby extconf.rb
make

