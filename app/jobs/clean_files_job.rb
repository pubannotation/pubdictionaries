class CleanFilesJob
  include Delayed::RecurringJob
  run_every 1.day
  run_at '1:00am'
  timezone 'Tokyo'
  queue 'general'
  def perform
  	to_delete = []
    Dir.foreach(TextAnnotator::RESULTS_PATH) do |filename|
      next if filename == '.' or filename == '..'
      filepath = TextAnnotator::RESULTS_PATH + filename
      to_delete << filepath if Time.now - File.mtime(filepath) > 1.day
    end
    File.delete(*to_delete)
  end
end