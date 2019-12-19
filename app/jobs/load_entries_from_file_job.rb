class LoadEntriesFromFileJob < Struct.new(:filename, :dictionary)
	include StateManagement

	def perform
    begin
      transaction_size = 1000
      num_entries = File.read(filename).each_line.count
      if @job
        @job.update_attribute(:num_items, num_entries)
        @job.update_attribute(:num_dones, 0)
      end

      normalizer_url = URI.parse("#{Rails.configuration.elasticsearch[:host]}/entries/_analyze")

      normalizer = {
        uri: normalizer_url,
        http: Net::HTTP::Persistent.new,
        post: Net::HTTP::Post.new(normalizer_url.request_uri, 'Content-Type' => 'application/json')
      }

      dictionary_empty = dictionary.entries.empty?
      new_entries = []
      File.foreach(filename).with_index do |line, i|
        label, id = Entry.read_entry_line(line)
        if label.nil?
          # invalid entry line detected.
          # output an error message or just ignore it.
        elsif dictionary_empty || dictionary.entries.find_by_label_and_identifier(label, id).nil?
          new_entries << [label, id]
          if new_entries.length >= transaction_size
            dictionary.add_entries(new_entries, normalizer)
            new_entries.clear
            if @job
              @job.update_attribute(:num_dones, i + 1)
            end
          end
        end
      end
      dictionary.add_entries(new_entries, normalizer) unless new_entries.empty?
      if @job
        @job.update_attribute(:num_dones, num_entries)
      end

      dictionary.compile
    rescue => e
      Delayed::Worker.logger.debug e.message + e.backtrace.join("\n")
      if @job
        @job.message = e.message
      end
      raise
    end

    normalizer && normalizer[:http] && normalizer[:http].shutdown
    File.delete(filename)
	end
end
