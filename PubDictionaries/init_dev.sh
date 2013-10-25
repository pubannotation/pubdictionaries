rm ./log/*
unicorn_rails -D -E development -c ../PubDictionaries/config/unicorn.rb
