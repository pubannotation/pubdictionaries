class CloneDictionaryJob < ApplicationJob
  def perform(source_dictionary, dictionary)
    begin
      dictionary.add_entries(source_dictionary.entries)
    rescue => e
      @job.message = e.message
    end
  end
end
