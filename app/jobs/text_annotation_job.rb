class TextAnnotationJob < ApplicationJob
  queue_as :annotation

  def perform(target, dictionaries, options, callback_url)
    single_target = false
    targets = if target.class == Array
      target
    else
      single_target = true
      [target]
    end

    if @job
      @job.update_attribute(:num_items, targets.length)
      @job.update_attribute(:num_dones, 0)
    end

    dictionaries.each{|dictionary| dictionary.compile! if dictionary.compilable?}

    annotator = TextAnnotator.new(dictionaries, options)

    annotation_result = []
    buffer = []
    buffer_size = 0
    targets.each_with_index do |t, i|
      t_size = t[:text].length
      if buffer.present? && (buffer_size + t_size > 100000)

        r = Ractor.new do
          annotator2, buffer2 = Ractor.recv
          Racter.yeild annotator2.annotate_batch(buffer2)
        end
        r.send [annotator, buffer]
        annotation_result += r.take

        @job.update_attribute(:num_dones, i) if @job
        buffer.clear
        buffer_size = 0
      end
      buffer << t
      buffer_size += t_size
    end

    unless buffer.empty?
      annotation_result += annotator.annotate_batch(buffer)
      @job.update_attribute(:num_dones, targets.length) if @job
    end

    annotation_result = annotation_result.first if single_target

    annotator.dispose

    if @job
      if options[:no_text]
        if annotation_result.class == Hash
          annotations_result.delete(:text)
        elsif annotation_result.respond_to?(:each)
          annotation_result.each{|ann| ann.delete(:text)}
        end
      end
      TextAnnotator::BatchResult.new(nil, @job.id).save!(annotation_result)
    end

    if callback_url
      Net::HTTP.post(URI.parse(callback_url), annotation_result.to_json, {'Content-type' => 'application/json'})
    end
  end

  def create_job_record(name, num_items, time)
    Job.create({name: name, queue_name: self.queue_name, active_job_id: self.job_id, registered_at: Time.current, num_items: num_items, time: time})
  end

  before_perform do |active_job|
    set_job(active_job)
    set_begun_at
  end

  after_perform do
    set_ended_at
    clean_annotation_jobs
    clean_files
  end

  private

  def clean_annotation_jobs
    jobs_to_delete = Job.to_delete
    jobs_to_delete.each{|j| j.destroy_if_not_running}
  end

  def clean_files
    to_delete = TextAnnotator::BatchResult.older_files 1.day
    File.delete(*to_delete)
  end
end
