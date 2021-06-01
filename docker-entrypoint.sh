#!/bin/bash
set -e

if [ $1 = 'rails' ] && [ $2 = 's' ] ; then
    rm -f /myapp/tmp/pids/server.pid
    bundle check || bundle
    rake db:create db:migrate
    echo "Entry.__elasticsearch__.create_index! force:true" | rails console
fi

exec "$@"
