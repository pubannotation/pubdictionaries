class EntriesController < ApplicationController
  # Requires authentication for all actions
  before_filter :authenticate_user!
 
  def create
    begin
      dictionary = Dictionary.active.editable(current_user).find_by_name(params[:dictionary_id])
      raise ArgumentError, "Cannot find the dictionary, #{params[:dictionary_id]}, in your management." if dictionary.nil?

      if params[:label].present? && params[:identifier].present?
        dictionary.add_entry(params[:label].strip, params[:identifier].strip)
      elsif params[:file].present?
        raise RuntimeError, "The last task is not yet dismissed. Please dismiss it and try again." if dictionary.jobs.count > 0
        source_filepath = params[:file].tempfile.path
        target_filepath = File.join('tmp', "upload-#{dictionary.name}-#{Time.now.to_s[0..18].gsub(/[ :]/, '-')}")
        FileUtils.cp source_filepath, target_filepath

        # job = LoadEntriesFromFileJob.new(target_filepath, dictionary)
        # job.perform

        delayed_job = Delayed::Job.enqueue LoadEntriesFromFileJob.new(target_filepath, dictionary), queue: :general
        Job.create({name:"Upload dictionary entries", dictionary_id:dictionary.id, delayed_job_id:delayed_job.id})
      end

      respond_to do |format|
        format.html {redirect_to :back}
      end
    # rescue => e
    #   respond_to do |format|
    #     format.html {redirect_to :back, notice: e.message}
    #   end
    end
  end

  def destroy
    begin
      dictionary = Dictionary.active.editable(current_user).find_by_name(params[:dictionary_id])
      raise ArgumentError, "Cannot find the dictionary" if dictionary.nil?

      entry = Entry.find(params[:id])
      raise ArgumentError, "Cannot find the entry" if entry.nil?

      dictionary.destroy_entry(entry)
      message = "1 entry deleted from the dictionary."
    end

    respond_to do |format|
      format.html{ redirect_to :back, notice: message }
    end
  end

  def empty
    begin
      dictionary = Dictionary.active.editable(current_user).find_by_name(params[:dictionary_id])
      raise ArgumentError, "Cannot find the dictionary" if dictionary.nil?
      raise RuntimeError, "The last task is not yet dismissed. Please dismiss it and try again." if dictionary.jobs.count > 0

      # job = EmptyEntriesJob.new(dictionary)
      # job.perform

      delayed_job = Delayed::Job.enqueue EmptyEntriesJob.new(dictionary), queue: :general
      Job.create({name:"Empty entries", dictionary_id:dictionary.id, delayed_job_id:delayed_job.id})

      respond_to do |format|
        format.html{ redirect_to :back }
      end
    rescue => e
      respond_to do |format|
        format.html{ redirect_to :back, notice: e.message }
      end
    end
  end
end
