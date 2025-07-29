class OllamaLlm
	def self.fetch_embedding(text)
		client.embeddings(
			{
				model: PubDic::EmbeddingServer::DefaultModel,
				prompt: text
			}
		).first["embedding"]
	end

	private

	def self.client
		@client ||= Ollama.new(
			credentials: { address: PubDic::EmbeddingServer::URL },
			options: { server_sent_events: true }
		)
	end
end
