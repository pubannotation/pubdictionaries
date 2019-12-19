class CleanAnnotationJobsJob
  include Delayed::RecurringJob
  run_every 1.day
  run_at '1:00am'
  timezone 'Tokyo'
  queue 'general'

  def perform
  	jobs_to_delete = Job.to_delete
  	jobs_to_delete.each{|j| j.destroy_if_not_running}
  end
end