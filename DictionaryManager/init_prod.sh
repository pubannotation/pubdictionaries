rm ./log/*
unicorn_rails -D -E production -c ../DictionaryManager/config/unicorn.rb
