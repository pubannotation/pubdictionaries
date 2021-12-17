class LoadEntriesFromFileJob < ApplicationJob
  queue_as :upload

  def perform(dictionary, filename)
    transaction_size = 1000

    # file preprocessing
    # TODO: at the moment, it is hard-coded. It should be improved.
    `/usr/bin/dos2unix #{filename}`
    `/usr/bin/cut -f1-3 #{filename} | sort -u -o #{filename}`

    num_entries = File.read(filename).each_line.count
    if @job
      @job.update_attribute(:num_items, num_entries)
      @job.update_attribute(:num_dones, 0)
    end

    analyzer_url = URI.parse("#{Rails.configuration.elasticsearch[:host]}/entries/_analyze")

    analyzer = {
      uri: analyzer_url,
      http: Net::HTTP::Persistent.new,
      post: Net::HTTP::Post.new(analyzer_url.request_uri, 'Content-Type' => 'application/json')
    }

    new_entries = []
    File.foreach(filename).with_index do |line, i|
      label, id, operator = Entry.read_entry_line(line)
      next if label.nil?

      mode = case operator
             when '-'
               Entry::MODE_BLACK
             when '+'
               Entry::MODE_WHITE
             else
               Entry::MODE_GRAY
             end

      matched = dictionary.entries.find_by_label_and_identifier(label, id)
      if matched.nil?
        new_entries << [label, id, mode]
        if new_entries.length >= transaction_size
          dictionary.add_entries(new_entries, analyzer)
          new_entries.clear
          if @job
            @job.update_attribute(:num_dones, i + 1)
          end
        end
      else
        case mode
        when Entry::MODE_BLACK
          unless matched.mode == Entry::MODE_BLACK
            matched.be_black!
            dictionary.decrement!(:entries_num)
          end
        when Entry::MODE_WHITE
          matched.be_white!
        when Entry::MODE_GRAY
          # do nothing
        end

        if @job
          @job.increment!(:num_dones)
        end
      end
      check_suspend_flag
    end

    dictionary.add_entries(new_entries, analyzer) unless new_entries.empty?
    @job.update_attribute(:num_dones, num_entries)

    dictionary.compile!

    analyzer && analyzer[:http] && analyzer[:http].shutdown
    File.delete(filename)
  end

  before_perform do |active_job|
    set_job(active_job)
    set_begun_at
  end

  after_perform do
    set_ended_at
  end
end
