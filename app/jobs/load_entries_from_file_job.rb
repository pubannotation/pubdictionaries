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
    raise ArgumentError, "Dictionary upload is only available when there are no dictionary entries." unless dictionary.empty?

    # First pass: count total entries for progress tracking
    num_entries = File.foreach(filename).count
    @job.update(num_items: num_entries, num_dones: 0)

    # Second pass: process entries in batches
    batch = []
    analyzer = BatchAnalyzer.new(dictionary)
    validation_skipped = []
    line_number = 0

    File.foreach(filename) do |line|
      line_number += 1
      original_line = line.dup
      label, id, tags = Entry.read_entry_line(line)

      if label.nil?
        # Track validation-skipped entries
        validation_skipped << { line_number: line_number, line: original_line.strip, reason: 'validation' }
        next
      end

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

    # Collect all skipped entries
    all_skipped = []

    # Add token-limit skipped entries
    all_skipped += analyzer.skipped_entries.map { |e| e.merge(reason: 'token_limit') }

    # Add validation-skipped entries (limit to first 100 to avoid huge metadata)
    all_skipped += validation_skipped.first(100)

    # Report skipped entries if any
    if all_skipped.any?
      Rails.logger.warn "[LoadEntriesFromFileJob] #{all_skipped.size} entries were skipped:"
      all_skipped.each do |entry|
        if entry[:reason] == 'token_limit'
          Rails.logger.warn "  - [Token limit] '#{entry[:label]}' (#{entry[:identifier]})"
        else
          Rails.logger.warn "  - [Validation] Line #{entry[:line_number]}: #{entry[:line].truncate(100)}"
        end
      end

      # Store skipped entries in job metadata for display in UI
      @job.update(metadata: { skipped_entries: all_skipped })
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
