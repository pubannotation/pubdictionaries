module EntriesHelper
  def is_url?(id)
    id =~ /^https?:/
  end

  def pub_annotation_search_url(entry, dictionary)
    base_url = "https://pubannotation.org/term_search"
    query_params = {
      "term_search_controller_query[block_type]" => 'sentence',
      "term_search_controller_query[terms]" => entry.identifier,
      "term_search_controller_query[predicates]" => '',
      "term_search_controller_query[projects]" => '',
      "term_search_controller_query[base_project]" => dictionary.associated_annotation_project,
      "term_search_controller_query[page]" => 1,
      "term_search_controller_query[per]" => 10,
    }

    "#{base_url}?#{query_params.to_query}"
  end
end
