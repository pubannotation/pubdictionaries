class EmptyEntriesJob < Struct.new(:dictionary)
	include StateManagement

	def perform
    begin
      ActiveRecord::Base.transaction do
        dictionary.empty_entries
      end
    rescue => e
			@job.message = e.message
    end
		# Doc.index_diff if Doc.diff_flag
	end
end
