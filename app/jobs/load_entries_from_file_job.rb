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
    # TODO: at the moment, it is hard-coded. It should be improved.
    `/usr/bin/dos2unix #{filename}`
    `/usr/bin/cut -f1-3 #{filename} | sort -u | sort -k3 -o #{filename}`

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
