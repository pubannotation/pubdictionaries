class Api::V1::EntriesController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    dictionary = Dictionary.editable(current_user).find_by(name: params[:dictionary_id])

    if dictionary.nil?
      render json: { error: "Could not find the dictionary, #{params[:dictionary_id]}." }, status: :not_found
      return
    end

    label = params[:label]&.strip
    if label.blank?
      render json: { error: "A label should be supplied." }, status: :bad_request
      return
    end

    identifier = params[:identifier]&.strip
    if identifier.blank?
      render json: { error: "An identifier should be supplied." }, status: :bad_request
      return
    end

    entry = dictionary.entries.find_by(label:, identifier:)
    if entry.present?
      render json: { error: "The entry #{entry} already exists in the dictionary." }, status: :conflict
      return
    end

    begin
      ActiveRecord::Base.transaction do
        success, entry = dictionary.create_entry(label, identifier, params[:tags])

        if success
          render json: { message: "The white entry #{entry} was created." }, status: :created
        else
          render json: { message: "The white entry #{entry} could not be created." }, status: :unprocessable_entity
        end
      end
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end
  end

  def destroy_entries
    begin
      dictionary = Dictionary.editable(current_user).find_by(name: params[:dictionary_id])

      if dictionary.nil?
        render json: { error: "Could not find the dictionary, #{params[:dictionary_id]}." }, status: :not_found
        return
      end

      if params[:entry_id].nil?
        render json: { error: "No entry to be deleted is selected" }, status: :bad_request
        return
      end

      ActiveRecord::Base.transaction do
        Entry.where(id: params[:entry_id]).destroy_all
        dictionary.update_entries_num
      end
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end

    render json: { message: "Entry was successfully deleted." }, status: :ok
  end

  def undo
    begin
      dictionary = Dictionary.editable(current_user).find_by(name: params[:dictionary_id])

      if dictionary.nil?
        render json: { error: "Cannot find the dictionary." }, status: :bad_request
        return
      end

      entry = Entry.find(params[:id])

      if entry.nil?
        render json: { error: "Cannot find the entry." }, status: :bad_request
        return
      end

      dictionary.undo_entry(entry)
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end

    render json: { message: "Entry was successfully undid." }, status: :ok
  end

  def upload_tsv
    begin
      dictionary = Dictionary.editable(current_user).find_by(name: params[:dictionary_id])

      if dictionary.nil?
        render json: { error: "Could not find the dictionary, #{params[:dictionary_id]}." }, status: :not_found
        return
      end

      if dictionary.jobs.count > 0
        render json: { error: "The last task is not yet dismissed. Please dismiss it and try again." }, status: :bad_request
        return
      end

      source_filepath = params[:file].tempfile.path
      target_filepath = File.join('tmp', "upload-#{dictionary.name}-#{Time.now.to_s[0..18].gsub(/[ :]/, '-')}")
      FileUtils.cp source_filepath, target_filepath

      active_job = LoadEntriesFromFileJob.perform_later(dictionary, target_filepath)
      active_job.create_job_record("Upload dictionary entries")

    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end

    render json: { message: "Upload dictionary entries task was successfully created." }, status: :accepted
  end
end
