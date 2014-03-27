#!/bin/bash

SCRIPT_NAME=`basename $0`
RAILS_ENV_TYPE=$1


if [ $# -ne 1 ]; then
	echo "Usage: $SCRIPT_NAME <development or production>"
else
	# 1. Stop the unicorn's master process.
	old_pid=`cat tmp/pids/unicorn.pid`
	if [ "$old_pid" == "" ]; then
		echo "Can not find the master process!"
	else
		echo "Kill an old master process"
		kill $old_pid
	fi

	# 2. Stop delayed_job deamon.
	if [ $1 == "development" ]; then
		RAILS_ENV=development script/delayed_job stop
	else
		RAILS_ENV=production script/delayed_job stop
	fi
fi