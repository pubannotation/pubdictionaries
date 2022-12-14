#!/bin/bash
set -e

if [ $1 = 'rails' ] && [ $2 = 's' ] ; then
    rm -f /myapp/tmp/pids/server.pid
    bundle check || bundle
    rake db:create db:migrate
    bin/rails runner script/create_index.rb
fi

exec "$@"
