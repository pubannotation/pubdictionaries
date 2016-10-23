class EmptyEntriesJob < Struct.new(:dictionary)
	include StateManagement

	def perform
    begin
      dictionary.empty_entries
    rescue => e
			@job.message = e.message
    end
	end
end
