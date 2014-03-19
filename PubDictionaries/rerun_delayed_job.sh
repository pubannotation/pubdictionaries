RAILS_ENV=development script/delayed_job stop
RAILS_ENV=development script/delayed_job -n 4 start