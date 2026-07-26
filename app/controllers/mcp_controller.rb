class McpController < ApplicationController
	include ActionController::Live

	skip_before_action :verify_authenticity_token
	before_action :set_cors_headers

	def options
		head :ok
	end

	# GET /.well-known/mcp.json — Class-2 manifest for browser widgets.
	# Publishes the same tool list as `tools/list` on the JSON-RPC endpoint,
	# wrapped in a manifest envelope so a widget can discover this host's
	# MCP tools with a single fetch and then POST tool_calls directly to
	# /mcp (bypassing any hub proxy). See llm_meta_client's
	# `fetchMcpManifest` / project_mcp_tool_classes memory.
	def well_known
		set_cors_headers
		manifest = {
			servers: [ {
				name: "pubdictionaries",
				url:  "#{request.base_url}/mcp",
				tools: list_tools[:tools]
			} ]
		}
		render json: manifest
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
	
	# MCP 2025-03-26 tool-annotation hints. All PubDictionaries tools currently
	# query the local DB without side effects, so they share the same base
	# hints — `title` varies per tool (added inline). See:
	# https://modelcontextprotocol.io/specification/2025-03-26/server/tools#tool-annotations
	#
	# Why NOT idempotentHint: per the spec, idempotentHint "is only meaningful
	# when destructiveHint is true" — for read-only tools, clients may already
	# assume idempotence, and asserting it here reads as "this IS destructive
	# but safe to retry", which is worse than silence.
	#
	# Why openWorldHint: false — this describes RUNTIME behavior (does the
	# tool reach outside its context at call time?). Ontologies inside the DB
	# have external origins, but querying them stays local.
	QUERY_TOOL_ANNOTATIONS = {
		readOnlyHint: true,
		destructiveHint: false,
		openWorldHint: false
	}.freeze

	def list_tools
		{
			tools: [
				{
					name: 'list_dictionaries',
					description: 'Get the list of available dictionaries from PubDictionaries. Optionally filter by a case-insensitive substring match against name or description.',
					inputSchema: {
						type: 'object',
						properties: {
							query: {
								type: 'string',
								description: 'Optional filter — case-insensitive substring matched against dictionary name or description (e.g. "anatomy").'
							}
						},
						required: []
					},
					annotations: QUERY_TOOL_ANNOTATIONS.merge(title: 'List Dictionaries')
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
					},
					annotations: QUERY_TOOL_ANNOTATIONS.merge(title: 'Get Dictionary Description')
				},
				{
					name: 'find_ids',
					description: 'Find identifiers of terms by referencing a specified dictionary. If no dictionary is specified, searches all public dictionaries.',
					inputSchema: {
						type: 'object',
						properties: {
							labels: {
								type: 'string',
								description: 'A comma-separated list of terms (English only)'
							},
							dictionary: {
								type: 'string',
								description: 'The name of the dictionary to lookup (optional - if not specified, searches all public dictionaries)'
							}
						},
						required: ['labels']
					},
					annotations: QUERY_TOOL_ANNOTATIONS.merge(title: 'Find IDs')
				},
				{
					name: 'search',
					description: 'Search for identifiers of terms by referencing a specified dictionary. If no dictionary is specified, searches all public dictionaries.',
					inputSchema: {
						type: 'object',
						properties: {
							labels: {
								type: 'string',
								description: 'A comma-separated list of terms (English only)'
							},
							dictionary: {
								type: 'string',
								description: 'The name of the dictionary to lookup (optional - if not specified, searches all public dictionaries)'
							}
						},
						required: ['labels']
					},
					annotations: QUERY_TOOL_ANNOTATIONS.merge(title: 'Search')
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
					},
					annotations: QUERY_TOOL_ANNOTATIONS.merge(title: 'Find Terms')
				},
				{
					name: 'text_annotation',
					description: 'Annotate free text against one or more dictionaries. Returns matched spans with their positions and identifiers.',
					inputSchema: {
						type: 'object',
						properties: {
							text: {
								type: 'string',
								description: 'The free text to annotate'
							},
							dictionaries: {
								type: 'string',
								description: 'A comma-separated list of dictionary names to annotate against'
							}
						},
						required: ['text', 'dictionaries']
					},
					annotations: QUERY_TOOL_ANNOTATIONS.merge(title: 'Text Annotation')
				}
			]
		}
	end
	
	def call_tool(tool_name, arguments)
		case tool_name
		when 'list_dictionaries'
			handle_list_dictionaries(arguments['query'])
		when 'get_dictionary_description'
			handle_get_dictionary_description(arguments['name'])
		when 'find_ids', 'search'
			handle_find_ids(arguments['labels'], arguments['dictionary'])
		when 'find_terms'
			handle_find_terms(arguments['ids'], arguments['dictionary'])
		when 'text_annotation'
			handle_text_annotation(arguments['text'], arguments['dictionaries'])
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

	def handle_list_dictionaries(query = nil)
		query = query.to_s.strip
		path = query.present? ? "/dictionaries.json?query=#{ERB::Util.url_encode(query)}" : '/dictionaries.json'
		response = make_internal_request(path)
		dictionaries = JSON.parse(response.body)

		payload = {
			dictionaries: dictionaries.map { |d| d.slice("name", "description", "maintainer", "entries_num") },
			link: view_url_for(:list_dictionaries, query: query)
		}

		json_content(payload)
	end
	
	def handle_get_dictionary_description(name)
		raise StandardError, "Dictionary name is required" if name.blank?

		encoded_name = ERB::Util.url_encode(name)
		response = make_internal_request("/dictionaries/#{encoded_name}/description")

		json_content(
			description: response.body.to_s,
			link: view_url_for(:dictionary_description, name: name)
		)
	end
	
	def handle_find_ids(labels, dictionary)
		raise StandardError, "Labels are required" if labels.blank?

		encoded_labels = ERB::Util.url_encode(labels)

		url = if dictionary.present?
			encoded_dictionary = ERB::Util.url_encode(dictionary)
			"/find_ids.json?labels=#{encoded_labels}&dictionary=#{encoded_dictionary}"
		else
			"/find_ids.json?labels=#{encoded_labels}"
		end

		response = make_internal_request(url)
		results = JSON.parse(response.body)

		json_content(
			identifiers: results,
			link: view_url_for(:find_ids, labels: labels, dictionary: dictionary)
		)
	end

	def handle_find_terms(ids, dictionary)
		raise StandardError, "IDs are required" if ids.blank?
		raise StandardError, "Dictionary name is required" if dictionary.blank?
		
		encoded_ids = ERB::Util.url_encode(ids)
		encoded_dictionary = ERB::Util.url_encode(dictionary)
		
		response = make_internal_request("/find_terms.json?identifiers=#{encoded_ids}&dictionary=#{encoded_dictionary}")
		results = JSON.parse(response.body)

		json_content(
			terms: results,
			link: view_url_for(:find_terms, ids: ids, dictionary: dictionary)
		)
	end
	
	def handle_text_annotation(text, dictionaries)
		raise StandardError, "Text is required" if text.blank?
		raise StandardError, "At least one dictionary must be specified" if dictionaries.blank?

		body = { text: text, dictionaries: dictionaries }.to_json
		response = make_internal_request('/text_annotation.json', method: :post, body: body)
		result = JSON.parse(response.body)

		annotated_text = result['text'] || text
		denotations    = result['denotations'] || []

		# Return a structured JSON object as the tool's text content so the LLM
		# can consume the annotation and the browsable link independently
		# (e.g. render the SIAF in chat AND emit the link separately). When
		# no denotations matched, `annotation` is the original text unchanged.
		json_content(
			annotation: denotations.empty? ? annotated_text : ::SimpleInlineTextAnnotation.generate(SiafSource.build(annotated_text, denotations)),
			link: view_url_for(:text_annotation, text: text, dictionaries: dictionaries)
		)
	end


	# Wrap a Ruby hash as an MCP `content: [{type:text, text:<JSON>}]` result.
	# Every tool response is pretty-printed JSON so the LLM (and humans
	# scanning the tool-call debug panel) can parse it consistently.
	def json_content(hash)
		{ content: [ { type: "text", text: JSON.pretty_generate(hash) } ] }
	end

	# Practical browser URL length. Beyond this, some browsers / proxies /
	# CDN edges reject or truncate — the click-through would 4xx instead of
	# usefully pre-filling the form.
	MAX_URL_QUERY_LEN = 1500

	def view_url_for(tool, **args)
		base = determine_base_url

		path = case tool
		when :list_dictionaries
			q = args[:query].to_s.strip
			q.empty? ? "/dictionaries" : "/dictionaries?query=#{ERB::Util.url_encode(q)}"

		when :dictionary_description
			"/dictionaries/#{ERB::Util.url_encode(args[:name].to_s)}"

		when :find_ids
			# Form param name is `label` (singular) — see app/views/lookup/find_ids.html.erb
			labels_enc = ERB::Util.url_encode(args[:labels].to_s)
			dict = args[:dictionary].to_s.strip
			if dict.present?
				"/dictionaries/#{ERB::Util.url_encode(dict)}/find_ids?label=#{labels_enc}"
			else
				"/find_ids?label=#{labels_enc}"
			end

		when :find_terms
			# Form param name is `identifiers` (plural) — see app/views/lookup/find_terms.html.erb.
			# dictionary is required at the MCP layer so it's always present here.
			"/dictionaries/#{ERB::Util.url_encode(args[:dictionary].to_s)}/find_terms?identifiers=#{ERB::Util.url_encode(args[:ids].to_s)}"

		when :text_annotation
			# Skip pre-filling `text` when it's too long for a URL query string —
			# `dictionaries` still rides along so the user's selection is preserved
			# and they can paste text into the form.
			text     = args[:text].to_s
			dict_enc = ERB::Util.url_encode(args[:dictionaries].to_s)
			text_enc = ERB::Util.url_encode(text)
			if text_enc.length <= MAX_URL_QUERY_LEN
				"/text_annotation?text=#{text_enc}&dictionaries=#{dict_enc}"
			else
				"/text_annotation?dictionaries=#{dict_enc}"
			end
		end

		"#{base}#{path}"
	end

	def make_internal_request(path, method: :get, body: nil)
		require 'net/http'

		# Build the full URL for the internal request
		base_url = determine_base_url
		uri = URI("#{base_url}#{path}")

		# Create HTTP client
		http = Net::HTTP.new(uri.host, uri.port)
		http.use_ssl = uri.scheme == 'https'

		# Set reasonable timeout
		http.open_timeout = 5
		# Annotation can be slow on large text — the sync endpoint runs the
		# full pipeline (tokenize → surface + semantic matching). 60s is a
		# reasonable ceiling for MCP tool use.
		http.read_timeout = method == :post ? 60 : 30

		# Make the request (GET by default; POST when a body needs to be sent)
		request = if method == :post
			r = Net::HTTP::Post.new(uri)
			r['Content-Type'] = 'application/json'
			r.body = body if body
			r
		else
			Net::HTTP::Get.new(uri)
		end
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