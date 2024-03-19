module EntriesHelper
  def is_url?(id)
    id =~ /^https?:/
  end

  def pub_annotation_search_url(entry, dictionary)
    base_url = "https://pubannotation.org/term_search"
    query_params = {
      block_type: 'sentence',
      terms: entry.identifier,
      predicates: '',
      projects: '',
      base_project: dictionary.associated_annotation_project,
      page: 1,
      per: 10,
    }

    "#{base_url}?#{query_params.to_query(:term_search_controller_query)}"
  end
end
