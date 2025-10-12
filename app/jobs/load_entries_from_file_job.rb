# ToDo : patterns upload
# ToDo : black/white entries upload

class LoadEntriesFromFileJob < ApplicationJob
  queue_as :upload

  def self.copy_file_and_perform(dictionary, source_filepath)
    target_filepath = File.join('tmp', "upload-#{dictionary.name}-#{Time.now.to_s[0..18].gsub(/[ :]/, '-')}")
    FileUtils.cp source_filepath, target_filepath

    active_job = perform_later(dictionary, target_filepath)
    active_job.create_job_record("Upload dictionary entries")
  end

  BATCH_SIZE = 10_000

  def perform(dictionary, filename, mode = nil)
    raise ArgumentError, "Dictionary upload is only available when there are no dictionary entries." unless dictionary.entries.empty?

    # First pass: count total entries for progress tracking
    num_entries = File.foreach(filename).count
    @job.update(num_items: num_entries, num_dones: 0)

    # Second pass: process entries in batches
    batch = []
    analyzer = BatchAnalyzer.new(dictionary)

    File.foreach(filename) do |line|
      label, id, tags = Entry.read_entry_line(line)
      next if label.nil?

      batch << [label, id, tags]

      # Flush batch when it reaches capacity
      if batch.size >= BATCH_SIZE
        check_suspension
        flush_batch(batch, analyzer)
        @job.increment!(:num_dones, BATCH_SIZE)
        batch.clear
      end
    end

    # Flush remaining entries
    unless batch.empty?
      flush_batch(batch, analyzer)
      @job.increment!(:num_dones, batch.size)
    end
  ensure
    analyzer&.shutdown
    File.delete(filename) if File.exist?(filename)
  end

  private

  def flush_batch(batch, analyzer)
    analyzer.add_entries(batch)
  rescue => e
    raise ArgumentError, "Entries are rejected: #{e.message} #{e.backtrace.join("\n")}."
  end

  def check_suspension
    raise Exceptions::JobSuspendError if suspended?
  end

  before_perform do |active_job|
    set_job(active_job)
    set_begun_at
  end

  after_perform do
    set_ended_at
  end
end
