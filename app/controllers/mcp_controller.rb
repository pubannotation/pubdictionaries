class McpController < ApplicationController
	include ActionController::Live

	skip_before_action :verify_authenticity_token
	before_action :set_cors_headers

	def options
		head :ok
	end

	def streamable_http
		if request.get?
			# GET request: Start streaming connection
			handle_stream
		elsif request.post?
			# POST request: Handle message
			handle_message
		else
			head :method_not_allowed
		end
	end

	private

	def handle_stream
		# Set up streaming HTTP headers
		response.headers['Content-Type'] = 'application/json'
		response.headers['Cache-Control'] = 'no-cache'
		response.headers['X-Accel-Buffering'] = 'no'

		# Important: Disable buffering in Rack
		response.stream.autoflush = true if response.stream.respond_to?(:autoflush=)

		begin
			# Send endpoint information as newline-delimited JSON
			endpoint_message = {
				jsonrpc: "2.0",
				method: "endpoint",
				params: {
					endpoint: "#{request.base_url}/mcp"
				}
			}
			response.stream.write("#{endpoint_message.to_json}\n")
			response.stream.flush if response.stream.respond_to?(:flush)

			# Keep connection alive with heartbeat
			loop do
				sleep 15
				ping_message = { type: "ping" }
				response.stream.write("#{ping_message.to_json}\n")
				response.stream.flush if response.stream.respond_to?(:flush)
			end
		rescue IOError, Errno::EPIPE, ActionController::Live::ClientDisconnected
			# Client disconnected
			Rails.logger.info "StreamableHttp client disconnected"
		ensure
			response.stream.close rescue nil
		end
	end

	def handle_message
		begin
			# Get request data from Rails params or request body
			if params[:mcp].present?
				request_data = params[:mcp].to_unsafe_h
			else
				request.body.rewind if request.body.respond_to?(:rewind)
				raw_body = request.body.read
				request_data = raw_body.present? ? JSON.parse(raw_body) : {}
			end

			# Validate JSON-RPC format
			unless valid_jsonrpc_request?(request_data)
				render json: error_response(request_data['id'], -32600, "Invalid Request")
				return
			end

			method_name = request_data['method']
			params = request_data['params'] || {}
			request_id = request_data['id']

			# Handle notifications (no response required)
			if method_name.start_with?('notifications/')
				handle_notification(method_name, params)
				render json: {}
				return
			end

			result = case method_name
							 when 'initialize'
								 handle_initialize(params)
							 when 'tools/list'
								 list_tools
							 when 'tools/call'
								 # Tool execution errors should be returned with isError: true
								 # so the LLM can see them and self-correct
								 begin
									 call_tool(params['name'], params['arguments'] || {})
								 rescue StandardError => e
									 Rails.logger.error "Tool execution error: #{e.message}"
									 {
										 content: [
											 {
												 type: 'text',
												 text: "Error: #{e.message}"
											 }
										 ],
										 isError: true
									 }
								 end
							 else
								 raise StandardError, "Method not found: #{method_name}"
							 end

			render json: success_response(request_id, result)

		rescue JSON::ParserError
			render json: error_response(nil, -32700, "Parse error")
		rescue StandardError => e
			# Protocol-level errors (invalid request, method not found, etc.)
			Rails.logger.error "MCP Protocol Error: #{e.message}"
			render json: error_response(request_data&.dig('id'), -32603, e.message)
		end
	end
	
	def set_cors_headers
		headers['Access-Control-Allow-Origin'] = '*'
		headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
		headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, X-Requested-With'
		headers['Access-Control-Max-Age'] = '86400'
	end
	
	def valid_jsonrpc_request?(data)
		data.is_a?(Hash) && 
		data['jsonrpc'] == '2.0' && 
		data.key?('method') &&
		data['method'].is_a?(String)
	end
	
	def success_response(id, result)
		{
			jsonrpc: "2.0",
			id: id,
			result: result
		}
	end
	
	def error_response(id, code, message)
		{
			jsonrpc: "2.0",
			id: id,
			error: {
				code: code,
				message: message
			}
		}
	end
	
	def list_tools
		{
			tools: [
				{
					name: 'list_dictionaries',
					description: 'Get the list of available dictionaries from PubDictionaries',
					inputSchema: {
						type: 'object',
						properties: {},
						required: []
					}
				},
				{
					name: 'get_dictionary_description',
					description: 'Retrieve the description for a specific dictionary identified by its name',
					inputSchema: {
						type: 'object',
						properties: {
							name: {
								type: 'string',
								description: 'The name of the dictionary'
							}
						},
						required: ['name']
					}
				},
				{
					name: 'find_ids',
					description: 'Find identifiers of terms by referencing a specified dictionary.',
					inputSchema: {
						type: 'object',
						properties: {
							labels: {
								type: 'string',
								description: 'A comma-separated list of terms (English only)'
							},
							dictionary: {
								type: 'string',
								description: 'The name of the dictionary to lookup'
							}
						},
						required: ['labels', 'dictionary']
					}
				},
				{
					name: 'search',
					description: 'Search for identifiers of terms by referencing a specified dictionary.',
					inputSchema: {
						type: 'object',
						properties: {
							labels: {
								type: 'string',
								description: 'A comma-separated list of terms (English only)'
							},
							dictionary: {
								type: 'string',
								description: 'The name of the dictionary to lookup'
							}
						},
						required: ['labels', 'dictionary']
					}
				},
				{
					name: 'find_terms',
					description: 'Find terms (labels) of identifiers by referencing a specified dictionary',
					inputSchema: {
						type: 'object',
						properties: {
							ids: {
								type: 'string',
								description: 'A comma-separated list of ids. Ensure adherence to the id format specified in each dictionary\'s description.'
							},
							dictionary: {
								type: 'string',
								description: 'The name of the dictionary to lookup'
							}
						},
						required: ['ids', 'dictionary']
					}
				}
			]
		}
	end
	
	def call_tool(tool_name, arguments)
		case tool_name
		when 'list_dictionaries'
			handle_list_dictionaries
		when 'get_dictionary_description'
			handle_get_dictionary_description(arguments['name'])
		when 'find_ids', 'search'
			handle_find_ids(arguments['labels'], arguments['dictionary'])
		when 'find_terms'
			handle_find_terms(arguments['ids'], arguments['dictionary'])
		else
			raise StandardError, "Unknown tool: #{tool_name}"
		end
	end

	def handle_notification(method_name, params)
		case method_name
		when 'notifications/initialized'
			Rails.logger.info "MCP Client initialized"
		else
			Rails.logger.info "Received notification: #{method_name}"
		end
	end

	def handle_initialize(params)
		# MCP initialization handshake
		protocol_version = params['protocolVersion']
		client_info = params['clientInfo']

		response = {
			protocolVersion: "2025-06-18",  # The protocol version we support
			capabilities: {
				tools: {}  # We support tools
			},
			serverInfo: {
				name: "PubDictionaries",
				version: "1.0.0"
			}
		}

		Rails.logger.info "MCP Initialize: Client #{client_info['name']} v#{client_info['version']}, Protocol: #{protocol_version}\n#{response}"

		response
	end

	# Tool implementations using HTTP requests to existing endpoints

	def handle_list_dictionaries
		response = make_internal_request('/dictionaries.json')
		dictionaries = JSON.parse(response.body)
		
		formatted_text = "Found #{dictionaries.length} dictionaries:\n\n" +
										dictionaries.map do |dict|
											"**#{dict['name']}**\n" +
											"Description: #{dict['description']}\n" +
											"Maintainer: #{dict['maintainer']}\n"
										end.join("\n")
		
		{
			content: [
				{
					type: 'text',
					text: formatted_text
				}
			]
		}
	end
	
	def handle_get_dictionary_description(name)
		raise StandardError, "Dictionary name is required" if name.blank?
		
		encoded_name = ERB::Util.url_encode(name)
		response = make_internal_request("/dictionaries/#{encoded_name}/description")
		
		{
			content: [
				{
					type: 'text',
					text: "Description for dictionary \"#{name}\":\n\n#{response.body}"
				}
			]
		}
	end
	
	def handle_find_ids(labels, dictionary)
		raise StandardError, "Labels are required" if labels.blank?
		raise StandardError, "Dictionary name is required" if dictionary.blank?
		
		encoded_labels = ERB::Util.url_encode(labels)
		encoded_dictionary = ERB::Util.url_encode(dictionary)
		
		response = make_internal_request("/find_ids.json?labels=#{encoded_labels}&dictionary=#{encoded_dictionary}")
		results = JSON.parse(response.body)
		
		formatted_results = results.map do |term, ids|
			"**#{term}**: #{ids.join(', ')}"
		end.join("\n")
		
		{
			content: [
				{
					type: 'text',
					text: "Found identifiers for terms in dictionary \"#{dictionary}\":\n\n#{formatted_results}"
				}
			]
		}
	end
	
	def handle_find_terms(ids, dictionary)
		raise StandardError, "IDs are required" if ids.blank?
		raise StandardError, "Dictionary name is required" if dictionary.blank?
		
		encoded_ids = ERB::Util.url_encode(ids)
		encoded_dictionary = ERB::Util.url_encode(dictionary)
		
		response = make_internal_request("/find_terms.json?identifiers=#{encoded_ids}&dictionary=#{encoded_dictionary}")
		results = JSON.parse(response.body)
		
		formatted_results = results.map do |id, data|
			"**#{id}**: #{data['label']} (from #{data['dictionary']})"
		end.join("\n")
		
		{
			content: [
				{
					type: 'text',
					text: "Found terms for identifiers in dictionary \"#{dictionary}\":\n\n#{formatted_results}"
				}
			]
		}
	end
	
	def make_internal_request(path)
		require 'net/http'
		
		# Build the full URL for the internal request
		base_url = determine_base_url
		uri = URI("#{base_url}#{path}")
		
		# Create HTTP client
		http = Net::HTTP.new(uri.host, uri.port)
		http.use_ssl = uri.scheme == 'https'
		
		# Set reasonable timeout
		http.open_timeout = 5
		http.read_timeout = 30
		
		# Make the request
		request = Net::HTTP::Get.new(uri)
		request['Accept'] = 'application/json'
		request['User-Agent'] = 'PubDictionaries-MCP/1.0'
		
		response = http.request(request)
		
		# Handle response
		unless response.is_a?(Net::HTTPSuccess)
			error_message = "Internal API request failed: #{response.code} #{response.message}"

			# Try to parse JSON error response
			if response.body && !response.body.empty?
				begin
					error_data = JSON.parse(response.body)
					if error_data['message']
						error_message = error_data['message']
					end
				rescue JSON::ParserError
					# Not JSON, use first 200 chars of response
					error_message += " - #{response.body[0, 200]}"
				end
			end

			raise StandardError, error_message
		end

		response
		
	rescue Net::OpenTimeout, Net::ReadTimeout
		raise StandardError, "Request timeout"
	rescue Net::HTTPError => e
		raise StandardError, "HTTP error: #{e.message}"
	rescue => e
		raise StandardError, "Request failed: #{e.message}"
	end
	
	def determine_base_url
		# Option 1: Use the current request's base URL (recommended)
		return request.base_url if request.present?
		
		# Option 2: Use environment-specific configuration
		case Rails.env
		when 'production'
			'https://pubdictionaries.org'
		when 'staging'
			'https://staging.pubdictionaries.org'
		else
			'http://localhost:3000'
		end
	end

end