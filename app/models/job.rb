class Job < ApplicationRecord
  include Rails.application.routes.url_helpers

  belongs_to :dictionary, optional: true

  scope :waiting, -> {where('begun_at IS NULL')}
  scope :running, -> {where('begun_at IS NOT NULL AND ended_at IS NULL')}
  scope :unfinished, -> {where('ended_at IS NULL')}
  scope :finished, -> {where('ended_at IS NOT NULL')}

  scope :to_delete, -> {where("name = 'Text annotation' AND ended_at < NOW() - INTERVAL '1 day'")}

  def self.time_for_tasks_to_go(queue_name)
    Job.joins("JOIN delayed_jobs on jobs.delayed_job_id = delayed_jobs.id").where('delayed_jobs.queue' => queue_name, begun_at: nil).sum(:time)
  end

  def self.number_of_tasks_to_go(queue_name)
    Delayed::Job.where(queue: queue_name, attempts: 0).count
  end

  def description_csv(host = nil)
    d = description(host)
    CSV.generate(col_sep: "\t") do |tsv|
      # tsv << [:key, :value]
      d.each do |key, value|
        tsv << [key, value]
      end
    end
  end

  def description(host = nil)
    d = {status: status.to_s.upcase}
    d.merge!({submitted_at: registered_at})
    d.merge!({started_at: begun_at}) unless begun_at.nil?
    case status
    when :done
      d.merge!({finished_at: ended_at})
      d.merge!({result_location: annotation_result_url(TextAnnotator::BatchResult.new(nil, id).filename, host: host, only_path: host.nil?)})
    when :error
      d.merge!({stopped_at: ended_at})
      d.merge!({error_message: message})
    else
      d.merge!({ETR: etr})
    end
    d
  end

  def status
    if error?
      :error
    elsif finished?
      :done
    elsif running?
      :in_progress
    else
      :in_queue
    end
  end

  def error?
    message.present?
  end

  def running?
    !begun_at.nil? && ended_at.nil?
  end

  def finished?
    !ended_at.nil?
  end

  def destroy_if_not_running
    case status
    when :in_queue
      ApplicationJob.cancel_adapter_class.new.cancel(active_job_id, queue_name)
      destroy
    when :error, :done
      destroy
    when :in_progress
      # do nothing
    end
  end

  def etr(queue_name = :annotation)
    if begun_at.nil?
      number_of_annotation_workers = 4
      time_for_queue = Job.time_for_tasks_to_go(:annotation) / number_of_annotation_workers
      time_for_queue + time
    elsif num_dones && num_dones > 0
      duration = Time.now.utc - begun_at
      pace = num_dones / duration
      (num_items - num_dones) / (pace * 2)
    else
      5
    end
  end
end
