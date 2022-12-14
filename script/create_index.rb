3.times do
  puts "Try to create index."
  Entry.__elasticsearch__.create_index! force:true
  puts "Index is created."
rescue Faraday::ConnectionFailed
  puts "Wait to starting Elasticsearch"
  sleep 3
end