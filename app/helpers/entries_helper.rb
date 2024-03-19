module EntriesHelper
  def is_url?(id)
    id =~ /^https?:/
  end

  def pub_annotation_search_url(entry, dictionary)
    "https://pubannotation.org/term_search?term_search_controller_query%5Bblock_type%5D=sentence&term_search_controller_query%5Bterms%5D=#{entry.identifier}&term_search_controller_query%5Bpredicates%5D=&term_search_controller_query%5Bbase_project%5D=#{dictionary.associated_annotation_project}&term_search_controller_query%5Bprojects%5D=&term_search_controller_query%5Bpage%5D=1&term_search_controller_query%5Bper%5D=10"
  end
end
