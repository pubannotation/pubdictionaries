rm ./log/*
unicorn_rails -D -E production -c ../PubDictionaries/config/unicorn.rb
