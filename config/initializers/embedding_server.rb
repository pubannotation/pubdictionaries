module PubDic
  module EmbeddingServer
    #URL = 'http://localhost:11434'
    URL = 'http://localhost:11435/api/embed'
    # EmbeddingModel = 'avr/sfr-embedding-mistral'
    # EmbeddingModel = 'nextfire/paraphrase-multilingual-minilm:l12-v2'
    # EmbeddingModel = 'jeffh/intfloat-multilingual-e5-small:f32'
    # DefaultModel = 'jeffh/intfloat-multilingual-e5-large:f32'
    DefaultModel = 'pubmedbert'

    # Batch processing configuration
    # BatchSize: Number of texts per embedding request (adjust based on server memory)
    # ParallelThreads: Number of concurrent requests (match server workers count)
    #
    # Development (local server with limited resources):
    BatchSize = 1000
    ParallelThreads = 1
    #
    # Production example (powerful server with 4 GPU workers):
    # BatchSize = 2000
    # ParallelThreads = 4
  end
end