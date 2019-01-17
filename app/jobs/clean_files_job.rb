class CleanFilesJob
  include Delayed::RecurringJob
  run_every 1.day
  run_at '1:00am'
  timezone 'Tokyo'
  queue 'general'

  def perform
  	to_delete = TextAnnotator::BatchResult.older_files 1.day
    File.delete(*to_delete)
  end
end