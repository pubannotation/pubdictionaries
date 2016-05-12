class CloneDictionaryJob < Struct.new(:source_dictionary, :dictionary)
	include StateManagement

	def perform
    begin
      ActiveRecord::Base.transaction do
        source_dictionary.entries.each do |e|
          dictionary.entries << e
        end
        dictionary.update_attribute(:entries_count, dictionary.entries.count)
      end
    rescue => e
			@job.message = e.message
    end
	end
end
