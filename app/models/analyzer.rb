class Analyzer
  def initialize
    uri = URI.parse("#{Rails.configuration.elasticsearch[:host]}/entries/_analyze")
    @http = Net::HTTP.new(uri.host, uri.port)
    @post = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'application/json')
  end

  def normalize(text, normalizer)
    raise ArgumentError, "Empty text" if text.blank?
    _text = text.tr('{}', '()')
    body = { analyzer: normalizer, text: _text }.to_json
    response = tokenize(body)

    JSON.parse(response.body, symbolize_names: true)[:tokens].map{ _1[:token] }.join('')
  end

  private

  def tokenize(body)
    @post.body = body
    begin
      response = @http.request(@post)
    rescue => e
      raise 'Certain NLP components are malfunctioning. Please contact the system administrator.'
    end

    raise response.body unless response.kind_of? Net::HTTPSuccess
    response
  end
end
