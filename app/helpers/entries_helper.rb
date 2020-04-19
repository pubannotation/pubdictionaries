module EntriesHelper
  def is_url?(id)
  	id =~ /^https?:/
  end
end
