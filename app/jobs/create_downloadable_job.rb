class CreateDownloadableJob < ApplicationJob
  queue_as :general

  def perform(dictionary)
    dictionary.create_downloadable!
  end

  before_perform do |active_job|
    set_job(active_job)
    set_begun_at
  end

  after_perform do
    set_ended_at
    destroy_job_record
  end
end
