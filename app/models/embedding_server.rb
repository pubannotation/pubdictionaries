require 'net/http'
require 'json'
require 'connection_pool'

class EmbeddingServerError < StandardError; end
class EmbeddingClientError < StandardError; end

class EmbeddingServer
	DEFAULT_MODEL = 'pubmedbert'

	# Connection pool configuration
	POOL_SIZE = 5  # Max number of persistent connections
	POOL_TIMEOUT = 5  # Timeout waiting for a connection from pool (seconds)

	# Fetch available models from the embedding server
	def self.available_models
		models_url = "#{PubDic::EmbeddingServer::BASE_URL}/api/models"
		uri = URI(models_url)
		response = Net::HTTP.get(uri)
		data = JSON.parse(response)
		data['models'] || []
	rescue => e
		Rails.logger.error("Failed to fetch embedding models: #{e.message}")
		[]
	end

	# Create a connection pool for HTTP connections
	# This significantly reduces overhead of establishing new connections
	def self.connection_pool
		@connection_pool ||= ConnectionPool.new(size: POOL_SIZE, timeout: POOL_TIMEOUT) do
			uri = URI(PubDic::EmbeddingServer::URL)
			http = Net::HTTP.new(uri.host, uri.port)
			http.read_timeout = 60
			http.open_timeout = 10
			http.keep_alive_timeout = 30
			http
		end
	end

	def self.fetch_embedding(text, model: PubDic::EmbeddingServer::DefaultModel)
		fetch_embeddings([text], model: model).first
	end

	def self.fetch_embeddings(texts, model: PubDic::EmbeddingServer::DefaultModel)
		uri = URI(PubDic::EmbeddingServer::URL)

		request_body = { input: texts, model: model }

		request = Net::HTTP::Post.new(uri.path.empty? ? '/' : uri.path)
		request['Content-Type'] = 'application/json'
		request.body = request_body.to_json

		Rails.logger.debug "Embedding API request: #{request_body.inspect}"

		# Use connection from pool
		response = connection_pool.with do |http|
			http.request(request)
		end

		if response.code == '200'
			result = JSON.parse(response.body)
			result['embeddings']
		else
			error_details = {
				status: response.code,
				message: response.message,
				body: response.body,
				request_body: request_body
			}
			Rails.logger.error "Embedding API error details: #{error_details.inspect}"

			# Categorize errors based on HTTP status codes
			case response.code.to_i
			when 400..499
				# Client errors (bad request, unauthorized, etc.) - don't retry
				raise EmbeddingClientError.new("Client error #{response.code}: #{response.message} - #{response.body}")
			when 500..599
				# Server errors - can retry
				raise EmbeddingServerError.new("Server error #{response.code}: #{response.message} - #{response.body}")
			else
				# Unknown status codes
				raise EmbeddingServerError.new("Unknown error #{response.code}: #{response.message} - #{response.body}")
			end
		end
	rescue => e
		Rails.logger.error "Failed to fetch embeddings: #{e.message}"
		raise e
	end
end
