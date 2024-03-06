class ExpandSynonymJobsController < ApplicationController
  def create
    begin
      dictionary = Dictionary.editable(current_user).find_by_name(params[:id])
      raise ArgumentError, "Cannot find the dictionary" if dictionary.nil?

      active_job = ExpandSynonymJob.perform_later(dictionary)
      active_job.create_job_record("Automatically expand synonyms for entries")

      respond_to do |format|
        format.html{ redirect_back fallback_location: root_path }
      end
    rescue => e
      respond_to do |format|
        format.html {redirect_to dictionary_path(dictionary), notice: e.message}
      end
    end
  end
end
