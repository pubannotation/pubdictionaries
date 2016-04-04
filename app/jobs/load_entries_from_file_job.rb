class LoadEntriesFromFileJob < Struct.new(:filename, :dictionary)
	include StateManagement

	def perform
    begin
      ActiveRecord::Base.transaction do
      	count = 0
        File.foreach(filename) do |line|
          label, id = Entry.read_entry_line(line)
          unless label.nil?
          	dictionary.entries << Entry.get_by_value(label, id)
          	count += 1
          end
        end
        dictionary.increment!(:entries_count, count)
      end
    rescue => e
			@job.message = e.message
    end
    File.delete(filename)
	end
end
