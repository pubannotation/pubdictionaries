class EntriesController < ApplicationController
  # Requires authentication for all actions
  before_action :authenticate_user!, except: [:index]

  # GET /dictionaries/dic1/entries?page=1&per_page=20
  def index
    dictionary = Dictionary.find_by_name(params[:dictionary_id])
    raise ArgumentError, "Couldnot find the dictionary: #{params[:dictionary_id]}." if dictionary.nil?

    entries = dictionary.entries.order("mode DESC").order(:label).page(params[:page]).per(params[:per_page])

    respond_to do |format|
      format.json { render json: entries }
    end
  rescue ArgumentError => e
    respond_to do |format|
      format.html {flash.now[:notice] = e.message}
      format.any {render json: {message:e.message}, status: :bad_request}
    end
  rescue => e
    respond_to do |format|
      format.html { redirect_to dictionaries_url, notice: e.message }
      format.json { head :unprocessable_content }
      format.tsv  { head :unprocessable_content }
    end
  end

  def create
    begin
      dictionary = Dictionary.editable(current_user).find_by_name(params[:dictionary_id])
      raise ArgumentError, "Could not find the dictionary, #{params[:dictionary_id]}." if dictionary.nil?

      label = params[:label].strip
      raise ArgumentError, "A label should be supplied." unless label.present?

      identifier = params[:identifier].strip
      raise ArgumentError, "An identifier should be supplied." unless identifier.present?

      entry = dictionary.entries.where(label:label, identifier:identifier).first
      raise ArgumentError, "The entry #{entry} already exists in the dictionary." unless entry.nil?

      ActiveRecord::Base.transaction do
        entry = dictionary.new_entry(label, identifier)

        tag_ids = params[:tags] || []
        entry.tag_ids = tag_ids

        if entry.save
          # dictionary.update_tmp_sim_string_db
        else
          raise "The white entry #{entry} could not be created."
        end
      end

      respond_to do |format|
        message = "The white entry #{entry} was created."
        format.html { redirect_back fallback_location: root_path, notice: message}
        format.json { render json: entry, status: :created }
      end

    rescue => e
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path, notice: e.message.slice(0, 1000)}
        format.json { head :unprocessable_content }
      end
    end

  end

  def upload_tsv
    begin
      dictionary = Dictionary.editable(current_user).find_by_name(params[:dictionary_id])

      raise ArgumentError, "Could not find the dictionary, #{params[:dictionary_id]}." if dictionary.nil?
      raise RuntimeError, "The last task is not yet dismissed. Please dismiss it and try again." if dictionary.jobs.count > 0

      mode = params[:mode]

      source_filepath = params[:file].tempfile.path
      target_filepath = File.join('tmp', "upload-#{dictionary.name}-#{Time.now.to_s[0..18].gsub(/[ :]/, '-')}")
      FileUtils.cp source_filepath, target_filepath

      # LoadEntriesFromFileJob.perform_now(dictionary, target_filepath)

      active_job = LoadEntriesFromFileJob.perform_later(dictionary, target_filepath, mode)
      active_job.create_job_record("Upload dictionary entries")
      message = ''

    rescue => e
      message = e.message
    end

    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, notice: message }
    end
  end

  def switch_to_black_entries
    begin
      dictionary = Dictionary.editable(current_user).find_by_name(params[:dictionary_id])
      raise ArgumentError, "Could not find the dictionary" if dictionary.nil?

      raise ArgumentError, "No entry to be deleted is selected" unless params[:entry_id].present?

      ActiveRecord::Base.transaction do
        entries = Entry.where(id: params[:entry_id])
        entries.each{|entry| entry.be_black!}
        dictionary.update_entries_num
      end
    rescue => e
      message = e.message
    end

    respond_to do |format|
      format.html{ redirect_back fallback_location: root_path, notice: message }
    end
  end

  def undo
    begin
      dictionary = Dictionary.editable(current_user).find_by_name(params[:dictionary_id])
      raise ArgumentError, "Cannot find the dictionary" if dictionary.nil?

      entry = Entry.find(params[:id])
      raise ArgumentError, "Cannot find the entry" if entry.nil?

      dictionary.undo_entry(entry)
    rescue => e
      message = e.message
    end

    respond_to do |format|
      format.html{
        if dictionary.entries.white.exists? || dictionary.entries.black.exists?
          redirect_back fallback_location: root_path, notice: message
        else
          redirect_to dictionary
        end
      }
    end
  end

  def confirm_to_white
    dictionary = Dictionary.editable(current_user).find_by_name(params[:dictionary_id])
    raise ArgumentError, "Cannot find the dictionary" if dictionary.nil?

    raise ArgumentError, "No entry to be confirmed is selected" unless params[:entry_id].present?

    dictionary.confirm_entries(params[:entry_id])

    respond_to do |format|
      format.html{
        if dictionary.entries.auto_expanded.exists?
          redirect_back fallback_location: root_path
        else
          redirect_to dictionary
        end
      }
    end
  rescue ArgumentError => e
    respond_to do |format|
      format.html {flash.now[:notice] = e.message}
    end
  rescue => e
    respond_to do |format|
      format.html { redirect_to dictionary, notice: e.message }
    end
  end

  def destroy_entries
    begin
      dictionary = Dictionary.editable(current_user).find_by_name(params[:dictionary_id])
      raise ArgumentError, "Could not find the dictionary" if dictionary.nil?

      raise ArgumentError, "No entry to be deleted is selected" unless params[:entry_id].present?

      Entry.where(id: params[:entry_id]).destroy_all
    rescue => e
      message = e.message
    end

    respond_to do |format|
      format.html{ redirect_back fallback_location: root_path, notice: message }
    end
  end
end
