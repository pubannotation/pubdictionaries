class LoadEntriesFromFileJob < Struct.new(:filename, :dictionary)
	include StateManagement

	def perform
    begin
      transaction_size = 1000
      num_entries = File.read(filename).each_line.count
      @job.update_attribute(:num_items, num_entries)
      @job.update_attribute(:num_dones, 0)

      new_entries = []
      File.foreach(filename).with_index do |line, i|
        label, id = Entry.read_entry_line(line)
        if label.nil?
          # invalid entry line detected.
          # output an error message or just ignore it.
        else
          new_entries << [label, id]
          if new_entries.length >= transaction_size
            dictionary.add_entries(new_entries)
            new_entries.clear
            @job.update_attribute(:num_dones, i + 1)
          end
        end
      end
      dictionary.add_entries(new_entries) unless new_entries.empty?
      @job.update_attribute(:num_dones, num_entries)

      dictionary.compile
    rescue => e
			@job.message = e.message
    end
    File.delete(filename)
	end
end
