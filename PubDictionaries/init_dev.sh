rm ./log/*
RAILS_ENV=development script/delayed_job -n 4 start
unicorn_rails -D -E development -c ../PubDictionaries/config/unicorn.rb
