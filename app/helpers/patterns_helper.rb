module PatternsHelper
  def is_url?(id)
  	id =~ /^https?:/
  end
end
