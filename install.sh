#!/bin/bash

cd simstring-1.0
./configure
cd swig/ruby
./prepare.sh --swig
ruby extconf.rb
make

