class Analyzer

  def initialize(use_persistent: false)
    @uri = URI.parse("#{Rails.configuration.elasticsearch[:host]}/entries/_analyze")
    @http =
      if use_persistent
        Net::HTTP::Persistent.new
      else
        Net::HTTP.new(@uri.host, @uri.port)
      end
    @post = Net::HTTP::Post.new(@uri.request_uri, 'Content-Type' => 'application/json')
  end

end
