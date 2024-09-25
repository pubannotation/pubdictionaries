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

  def perform(dictionary, filename, mode = nil)
    unless dictionary.entries.empty?
      @job.message = "Dictionary upload is only available when there are no dictionary entries."
      File.delete(filename)
      return
    end

    # file preprocessing
    format_and_rewrite(filename)

    num_entries = File.read(filename).each_line.count
    if @job
      @job.update_attribute(:num_items, num_entries)
      @job.update_attribute(:num_dones, 0)
    end

    buffer = LoadEntriesFromFileJob::BufferToStore.new(dictionary)

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
  ensure
    File.delete(filename)
  end

  before_perform do |active_job|
    set_job(active_job)
    set_begun_at
  end

  after_perform do
    set_ended_at
  end

  private

  def format_and_rewrite(filename)
    lines = File.readlines(filename)

    cut_lines = lines.map do |line|
      fields = line.split("\t")
      fields[0..2].join("\t")
    end

    sorted_lines = cut_lines.uniq.sort_by do |line|
      fields = line.split("\t")
      fields[2]
    end

    File.open(filename, "w") do |file|
      sorted_lines.each { |line| file.puts(line) }
    end
  end
end
