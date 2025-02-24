class OllamaLlm
	def self.fetch_embedding(text)
		client.embeddings(
			{
				model: PubDic::Ollama::EmbeddingModel,
				prompt: text
			}
		).first["embedding"]
	end

	private

	def self.client
		@client ||= Ollama.new(
			credentials: { address: PubDic::Ollama::Address },
			options: { server_sent_events: true }
		)
	end
end
