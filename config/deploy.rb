require "rvm/capistrano"
require "bundler/capistrano"

set :user, 'nlp'
set :domain, 'cl30.dbcls.jp'
set :application, 'PubDictionaries'

# file paths
# set :repository,  "#{user}@#{domain}:git/#{application}.git"
set :repository,  "#{user}@cl30.dbcls.jp:git/#{application}.git"
set :deploy_to, "/opt/services/nlp/work/#{domain}"
set :ssh_options, {:forward_agent => true}

# distribute your applications across servers (the instructions below put them
#   all on the same server, defined above as 'domain', adjust as necessary)
role :web, domain                          # Your HTTP server, Apache/etc
role :app, domain                          # This may be the same as your `Web` server
role :db,  domain, :primary => true        # This is where Rails migrations will run
# role :db,  "your slave db-server here"

# you might need to set this if you aren't seeing password prompts
# default_run_options[:pty] = true

# As Capistrano executes in a non-interactive mode and therefore doesn't cause
# any of your shell profile scripts to be run, the following might be needed
# if (for example) you have locally installed gems or applications. Note:
# this needs to contain the full values for the variables set, not simply
# the deltas.
# default_environment['PATH']='<your paths>:/usr/local/bin:/usr/bin:/bin'
# default_environment['GEM_PATH']='<your paths>:/usr/lib/ruby/gems/1.8

set :deploy_via, :remote_cache
set :scm_verbose, true
set :use_sudo, false
set :branch, 'master'
# set :scm, :git # You can set :scm explicitly or Capistrano will make an intelligent guess based on known version control directory names
# Or: `accurev`, `bzr`, `cvs`, `darcs`, `git`, `mercurial`, `perforce`, `subversion` or `none`
set :scm, 'git'

set :rvm_ruby_string, :local
set :rvm_autolibs_flag, "read-only"

before 'deploy:setup', 'rvm:install_rvm'
before 'deploy:setup', 'rvm:install_ruby'

# If you are using Passenger mod_rails uncomment this:
# namespace :deploy do
#   task :start do ; end
#   task :stop do ; end
#   task :restart, :roles => :app, :except => { :no_release => true } do
#     run "#{try_sudo} touch #{File.join(current_path,'tmp','restart.txt')}"
#   end
# end

# if you want to clean up old releases on each deploy uncomment this:
# after "deploy:restart", "deploy:cleanup"

# if you're still using the script/reaper helper you will need
# these http://github.com/rails/irs_process_scripts

# optional task to reconfigure databases
after "deploy:update_code", :bundle_install
desc "install the necessary prerequisites"
task :bundle_install, :roles => :app do
  # run "bundle config build.pg --with-pg-dir=/usr/pgsql-9.1"
  run "cd #{release_path} && bundle install"
end







