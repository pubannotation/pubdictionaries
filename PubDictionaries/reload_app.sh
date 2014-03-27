#!/bin/bash

SCRIPT_NAME=`basename $0`
RAILS_ENV_TYPE=$1


if [ $# -ne 1 ]; then
	echo "Usage: $SCRIPT_NAME <development or production>"
else
	# 1. Rerun the App.
	rm ./log/*

	old_pid=`cat tmp/pids/unicorn.pid`
	if [ "$old_pid" == "" ]; then
		echo "Can not find the master process!"
	else
		# Shut down the old process gracefully and reload it
		echo "Kill an old master process and reload a new one"
		kill -s USR2 $old_pid
	fi

	# 2. Rerun the delayed_job process.
	if [ $1 == "development" ]; then
		RAILS_ENV=development script/delayed_job stop
		RAILS_ENV=development script/delayed_job -n 4 start
	else
		RAILS_ENV=production script/delayed_job stop
		RAILS_ENV=production script/delayed_job -n 4 start
	fi
fi
	
