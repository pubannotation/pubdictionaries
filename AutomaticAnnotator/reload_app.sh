#!/bin/bash

rm ./log/*

# Find the pid of an old master process
old_pid=`cat tmp/pids/unicorn.pid`

if [ "$old_pid" == "" ]; then
	echo "Can not find the master process!"
else
	# Shut down the old process gracefully and reload it
	echo "Kill an old master process and reload a new one"
	kill -s USR2 $old_pid
fi
