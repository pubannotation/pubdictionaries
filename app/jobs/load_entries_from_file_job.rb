class LoadEntriesFromFileJob < Struct.new(:filename, :dictionary)
	include StateManagement

	def perform
    begin
      ActiveRecord::Base.transaction do
      	count = 0
        File.foreach(filename) do |line|
          label, uri = Entry.read_entry_line(line)
          unless label.nil?
            entry = Entry.get_by_value(label, uri)
          	dictionary.entries << entry
          	count += 1
          end
        end
        dictionary.increment!(:entries_count, count)
      end
      begun_at = @job.begun_at
      # Label.__elasticsearch__.import query: -> {where('created_at > ?', begun_at)}
    rescue => e
			@job.message = e.message
    end
	end
end
