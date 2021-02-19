# This file is used by Rack-based servers to start the application.

require_relative "config/environment"
CleanFilesJob.schedule!
CleanAnnotationJobsJob.schedule!

run Rails.application
Rails.application.load_server
