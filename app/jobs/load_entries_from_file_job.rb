class LoadEntriesFromFileJob < Struct.new(:filename, :dictionary)
	include StateManagement

	def perform
    begin
      ActiveRecord::Base.transaction do
      	count = 0
        File.foreach(filename) do |line|
          label, id = Entry.read_entry_line(line)
          unless label.nil?
            e = Entry.get_by_value(label, id)
            unless dictionary.entries.include?(e)
              dictionary.entries << e
              e.label.__elasticsearch__.update_document
              count += 1
            end
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
