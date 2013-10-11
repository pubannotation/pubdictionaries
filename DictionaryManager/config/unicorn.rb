# Application root directory
rails_env = ENV['RAILS_ENV'] || 'production'

# production_root  = "/opt/services/nlp/work/PubDictionaries/DictionaryManager"
production_root = `pwd`.gsub("\n","") 
development_root = `pwd`.gsub("\n","") 


working_directory   (rails_env == 'production' ? production_root : development_root)
worker_processes    (rails_env == 'production' ? 4 : 2)
preload_app         true
timeout             99999


if rails_env == 'production'
	listen        "#{production_root}/tmp/sockets/unicorn.sock", :backlog => 2048
	pid           "#{production_root}/tmp/pids/unicorn.pid"
	stderr_path   "#{production_root}/log/unicorn.stderr.log"
	stdout_path   "#{production_root}/log/unicorn.stdout.log"
else
	listen        "#{development_root}/tmp/sockets/unicorn.sock", :backlog => 10240
	pid           "#{development_root}/tmp/pids/unicorn.pid"
	stderr_path   "#{development_root}/log/unicorn.stderr.log"
	stdout_path   "#{development_root}/log/unicorn.stdout.log"
end


before_fork do |server, worker|
	# the following is highly recomended for Rails + "preload_app true"
	# as there's no need for the master process to hold a connection
	if defined?(ActiveRecord::Base)
	  ActiveRecord::Base.connection.disconnect!
	end
 
	# Before forking, kill the master process that belongs to the .oldbin PID.
	# This enables 0 downtime deploys.
	old_pid = (rails_env == 'production') ? "#{production_root}/tmp/pids/unicorn.pid.oldbin" : "#{development_root}/tmp/pids/unicorn.pid.oldbin"
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


