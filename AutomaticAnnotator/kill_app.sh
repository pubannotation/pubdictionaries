#!/bin/bash

# Remove old log files
rm ./log/*

# Find the pid of an old master process
old_pid=`cat tmp/pids/unicorn.pid`

if [ "$old_pid" == "" ]; then
	echo "Can not find the master process!"
else
	echo "Kill an old master process"
	kill $old_pid
fi
