class CloneDictionaryJob < ApplicationJob
  def perform(source_dictionary, dictionary)
    dictionary.add_entries(source_dictionary.entries)
  end
end
