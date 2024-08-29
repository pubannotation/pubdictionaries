class Api::V1::EntriesController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :set_dictionary
  rescue_from Exceptions::DictionaryNotFoundError, with: :dictionary_not_found

  def create
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

    entry = @dictionary.entries.find_by(label:, identifier:)
    if entry.present?
      render json: { error: "The entry #{entry} already exists in the dictionary." }, status: :conflict
      return
    end

    begin
      entry = @dictionary.create_entry!(label, identifier, params[:tags])

      render json: { message: "The white entry #{entry} was created." }, status: :created
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end
  end

  def destroy_entries
    if params[:entry_id].nil?
      render json: { error: "No entry to be deleted is selected" }, status: :bad_request
      return
    end

    entries = Entry.where(id: params[:entry_id])

    if entries.empty?
      render json: { error: "Could not find the entries, #{params[:entry_id]}" }, status: :not_found
      return
    end

    begin
      ActiveRecord::Base.transaction do
        entries.destroy_all
        @dictionary.update_entries_num
      end

      render json: { message: "Entry was successfully deleted." }, status: :ok
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end
  end

  def undo
    entry = Entry.find(params[:id])

    if entry.nil?
      render json: { error: "Cannot find the entry." }, status: :bad_request
      return
    end

    @dictionary.undo_entry(entry)

    render json: { message: "Entry was successfully undid." }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :internal_server_error
  end

  def upload_tsv
    if @dictionary.jobs.count > 0
      render json: { error: "The last task is not yet dismissed. Please dismiss it and try again." }, status: :bad_request
      return
    end

    begin
      LoadEntriesFromFileJob.prepare_file_and_perform(@dictionary, params[:file])

      render json: { message: "Upload dictionary entries task was successfully created." }, status: :accepted
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end
  end

  private

  def set_dictionary
    @dictionary = Dictionary.editable(current_user).find_by(name: params[:dictionary_id])
    raise Exceptions::DictionaryNotFoundError if @dictionary.nil?
  end

  def dictionary_not_found
    render json: { error: "Could not find the dictionary, #{params[:dictionary_id]}." }, status: :not_found
  end
end
