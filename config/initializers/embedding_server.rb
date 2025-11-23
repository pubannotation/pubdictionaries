module PubDic
  module EmbeddingServer
    #URL = 'http://localhost:11434'
    BASE_URL = 'http://localhost:11435'
    URL = "#{BASE_URL}/api/embed"
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
    ParallelThreads = 2
    #
    # Production example (powerful server with 4 GPU workers):
    # BatchSize = 2000
    # ParallelThreads = 4

    # Span pre-filtering for semantic search
    # Reduces embedding requests by skipping unlikely dictionary matches
    #
    # MinSpanLength: Minimum character length for semantic search (default: 3)
    # SkipNumericSpans: Skip spans that are purely numeric (default: true)
    MinSpanLength = 3
    SkipNumericSpans = true
  end
end