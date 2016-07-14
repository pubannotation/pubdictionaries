class CloneDictionaryJob < Struct.new(:source_dictionary, :dictionary)
	include StateManagement

	def perform
    begin
      dictionary.add_entries(source_dictionary.entries)
    rescue => e
			@job.message = e.message
    end
	end
end
