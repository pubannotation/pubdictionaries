class LoadEntriesFromFileJob < Struct.new(:filename, :dictionary)
	include StateManagement

	def perform
    begin
      ActiveRecord::Base.transaction do
      	count = 0
        File.foreach(filename) do |line|
          label, uri = Entry.read_entry_line(line)
          unless label.nil?
          	dictionary.entries << Entry.get_by_value(label, uri)
          	count += 1
          end
        end
        dictionary.increment!(:entries_count, count)
      end
    rescue => e
			@job.message = e.message
    end
		# Doc.index_diff if Doc.diff_flag
	end
end
