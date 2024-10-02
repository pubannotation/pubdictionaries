#!/bin/bash
set -e

if [ $1 = 'rails' ] && [ $2 = 's' ] ; then
    bin/rails runner script/create_index.rb
    bin/setup
    rm -f /myapp/tmp/pids/server.pid
fi

exec "$@"
