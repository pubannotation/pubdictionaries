rails_env = ENV['RAILS_ENV'] || 'production'

#if rails_env == 'production'
#	root = '/opt/services/nlp/work/PubDicWebServices'
#else
#	root = '/Users/priancho/work/PubDicWebServices'
#end
root = `pwd`.gsub("\n","")

working_directory   root
worker_processes    2
timeout             600
preload_app         true

listen              "#{root}/tmp/sockets/unicorn.sock", :backlog => 64
pid                 "#{root}/tmp/pids/unicorn.pid"
stderr_path         "#{root}/log/unicorn.stderr.log"
stdout_path         "#{root}/log/unicorn.stdout.log"


before_fork do |server, worker|
	# the following is highly recomended for Rails + "preload_app true"
	# as there's no need for the master process to hold a connection
	if defined?(ActiveRecord::Base)
	  ActiveRecord::Base.connection.disconnect!
	end
 
	# Before forking, kill the master process that belongs to the .oldbin PID.
	# This enables 0 downtime deploys.
	old_pid = "#{root}/tmp/pids/unicorn.pid.oldbin"
	if File.exists?(old_pid) && server.pid != old_pid
	  begin
	    Process.kill("QUIT", File.read(old_pid).to_i)
	  rescue Errno::ENOENT, Errno::ESRCH
	    # someone else did our job for us
	  end
	end
end
 
after_fork do |server, worker|
	# the following is *required* for Rails + "preload_app true",
	if defined?(ActiveRecord::Base)
	  ActiveRecord::Base.establish_connection
	end
 
	# if preload_app is true, then you may also want to check and
	# restart any other shared sockets/descriptors such as Memcached,
	# and Redis.  TokyoCabinet file handles are safe to reuse
	# between any number of forked children (assuming your kernel
	# correctly implements pread()/pwrite() system calls)
end
