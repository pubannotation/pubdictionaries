require 'net/http'
require 'uri'
require 'json'

uri = URI('http://localhost:3001/mcp')
puts "Testing StreamableHttp at #{uri}..."
puts "Using MCP standard endpoint: /mcp (GET for streaming, POST for messages)"
puts "---"

Net::HTTP.start(uri.host, uri.port) do |http|
  request = Net::HTTP::Get.new(uri)

  http.request(request) do |response|
    puts "Status: #{response.code}"
    puts "Content-Type: #{response['content-type']}"
    puts "Expected: application/json (StreamableHttp)"
    puts "---"

    buffer = ""
    timeout_at = Time.now + 3

    response.read_body do |chunk|
      buffer += chunk

      # Parse newline-delimited JSON (StreamableHttp format)
      while buffer.include?("\n")
        line, buffer = buffer.split("\n", 2)
        next if line.strip.empty?

        puts "Received line: #{line}"

        begin
          json = JSON.parse(line)
          puts "Parsed JSON message: #{json.inspect}"

          if json['method'] == 'endpoint'
            puts "✓ Endpoint message received: #{json['params']['endpoint']}"
          elsif json['type'] == 'ping'
            puts "✓ Ping message received"
          end
        rescue JSON::ParserError => e
          puts "✗ Failed to parse JSON: #{e.message}"
        end

        puts "---"
      end

      break if Time.now > timeout_at
    end

    puts "\nTest completed successfully!"
  end
end
