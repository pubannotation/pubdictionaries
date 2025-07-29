require 'net/http'
require 'json'

class EmbeddingServer
	EMBEDDING_API_URL = 'http://localhost:11435/api/embed'
	DEFAULT_MODEL = 'pubmedbert'

	def self.fetch_embedding(text, model: PubDic::EmbeddingServer::DefaultModel)
		fetch_embeddings([text], model: model).first
	end

	def self.fetch_embeddings(texts, model: PubDic::EmbeddingServer::DefaultModel)
		uri = URI(PubDic::EmbeddingServer::URL)
		http = Net::HTTP.new(uri.host, uri.port)
		http.read_timeout = 60

		request_body = { input: texts, model: model }

		request = Net::HTTP::Post.new(uri)
		request['Content-Type'] = 'application/json'
		request.body = request_body.to_json

		Rails.logger.debug "Embedding API request: #{request_body.inspect}"

		response = http.request(request)

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
