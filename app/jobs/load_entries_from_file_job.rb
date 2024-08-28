# ToDo : patterns upload
# ToDo : black/white entries upload

class LoadEntriesFromFileJob < ApplicationJob
  queue_as :upload

  class BufferToStore
    BUFFER_SIZE = 10000

    def initialize(dictionary)
      @dictionary = dictionary

      @entries = []
      @patterns = []

      analyzer_url = URI.parse("#{Rails.configuration.elasticsearch[:host]}/entries/_analyze")
      @analyzer = {
        uri: analyzer_url,
        http: Net::HTTP::Persistent.new,
        post: Net::HTTP::Post.new(analyzer_url.request_uri, 'Content-Type' => 'application/json')
      }

      @num_skipped_entries = 0
      @num_skipped_patterns = 0
    end

    def add_entry(label, identifier, tags)
      # case mode
      # when EntryMode::PATTERN
      #   buffer_pattern(label, identifier)
      # else
      #   buffer_entry(label, identifier, mode)
      # end
      buffer_entry(label, identifier, tags)
    end

    def finalize
      flush_entries unless @entries.empty?
      flush_patterns unless @patterns.empty?
      @analyzer && @analyzer[:http] && @analyzer[:http].shutdown
    end

    def result
      [@num_skipped_entries, @num_skipped_patterns]
    end

    private

    def buffer_entry(label, identifier, tags)
      matched = entries_any? && @dictionary.entries.where(label:label, identifier:identifier)&.first
      if matched
        # case mode
        # when EntryMode::GRAY
        #   @num_skipped_entries += 1
        # when EntryMode::WHITE
        #   matched.be_white!
        # when EntryMode::BLACK
        #   matched.be_black!
        # else
        #   raise ArgumentError, "Unexpected mode: #{mode}"
        # end
        @num_skipped_entries += 1
      else
        @entries << [label, identifier, tags]
      end
      flush_entries if @entries.length >= BUFFER_SIZE
    end

    def buffer_pattern(expression, identifier)
      matched = patterns_any? && @dictionary.patterns.where(expression:expression, identifier:identifier)&.first
      if matched
        @num_skipped_patterns += 1
      else
        @patterns << [expression, identifier]
      end
      flush_patterns if @patterns.length >= BUFFER_SIZE
    end

    def flush_entries
      @dictionary.add_entries(@entries, @analyzer)
      @entries.clear
    end

    def flush_patterns
      @dictionary.add_patterns(@patterns)
      @patterns.clear
    end

    # It is supposed to memorize whether the entries of the dictionary are empty when the class is initialized.
    def entries_any?
      @entries_any_p ||= !@dictionary.entries.empty?
    end

    # It is supposed to memorize whether the patterns of the dictionary are empty when the class is initialized.
    def patterns_any?
      @patterns_any_p ||= !@dictionary.patterns.empty?
    end
  end

  def self.prepare_file_and_perform(dictionary, uploaded_file)
    source_filepath = uploaded_file.tempfile.path
    target_filepath = File.join('tmp', "upload-#{dictionary.name}-#{Time.now.to_s[0..18].gsub(/[ :]/, '-')}")
    FileUtils.cp source_filepath, target_filepath

    active_job = perform_later(dictionary, target_filepath)
    active_job.create_job_record("Upload dictionary entries")
  end

  def perform(dictionary, filename, mode = nil)
    # file preprocessing
    # TODO: at the moment, it is hard-coded. It should be improved.
    `/usr/bin/dos2unix #{filename}`
    `/usr/bin/cut -f1-3 #{filename} | sort -u | sort -k3 -o #{filename}`

    num_entries = File.read(filename).each_line.count
    if @job
      @job.update_attribute(:num_items, num_entries)
      @job.update_attribute(:num_dones, 0)
    end

    buffer = BufferToStore.new(dictionary)

    File.open(filename, 'r') do |f|
      f.each_line do |line|
        label, id, tags = Entry.read_entry_line(line)
        next if label.nil?

        buffer.add_entry(label, id, tags)

        @job.increment!(:num_dones) if @job

        if suspended?
          buffer.finalize
          dictionary.compile!
          File.delete(filename)
          raise Exceptions::JobSuspendError
        end
      end
    end

    buffer.finalize
    # dictionary.compile!
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
