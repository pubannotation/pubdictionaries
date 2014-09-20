rm ./log/*
RAILS_ENV=production script/delayed_job -n 4 start
unicorn_rails -D -E production -c ../PubDictionaries/config/unicorn.rb
