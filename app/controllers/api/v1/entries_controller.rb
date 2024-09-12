class Api::V1::EntriesController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_token
  before_action :set_dictionary

  rescue_from StandardError, with: :handle_standard_error
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

    entry = @dictionary.create_entry!(label, identifier, params[:tags])

    render json: { message: "The white entry #{entry} was created." }, status: :created
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

    entries.destroy_all

    render json: { message: "Entry was successfully deleted." }, status: :ok
  end

  def undo
    entry = Entry.find(params[:id])

    if entry.nil?
      render json: { error: "Cannot find the entry." }, status: :bad_request
      return
    end

    @dictionary.undo_entry(entry)

    render json: { message: "Entry was successfully undid." }, status: :ok
  end

  def upload_tsv
    if @dictionary.jobs.any? && params[:force] == 'true'
      @dictionary.jobs.last.destroy_if_not_running
    end

    if @dictionary.jobs.count > 0
      if @dictionary.jobs.last.running?
        render json: { error: "The last task is still in progress. Please wait a moment and try again later." }, status: :conflict
      else
        render json: {
          error: "The last task is not yet dismissed. Please dismiss it and try again.",
          task_dismiss_instruction: "To dismiss the task, send a DELETE request to /api/v1/jobs/#{@dictionary.jobs.last.id} ."
        }, status: :conflict
      end

      return
    end

    unless @dictionary.uploadable?
      render json: { error: t('message.upload_disabled'), status: :bad_request }
      return
    end

    source_filepath = params[:file].tempfile.path
    LoadEntriesFromFileJob.copy_file_and_perform(@dictionary, source_filepath)

    render json: { message: "Upload dictionary entries task was successfully created." }, status: :accepted
  end

  private

  def authenticate_token
    if token
      sign_in(token.user)
    else
      render_token_invalid_error
    end
  end

  def token
    bearer_token = bearer_token_in(request.headers)
    AccessToken.find_by(token: bearer_token) if bearer_token
  end

  def bearer_token_in(headers)
    case headers['Authorization']
    in /^Bearer (.+)$/
      Regexp.last_match(1)
    else
      nil
    end
  end

  def render_token_invalid_error
    render json: { error: "The access token is missing or invalid." }, status: :unauthorized
    response.headers['WWW-Authenticate'] = 'Bearer'
  end

  def set_dictionary
    @dictionary = Dictionary.editable(current_user).find_by(name: params[:dictionary_id])
    raise Exceptions::DictionaryNotFoundError if @dictionary.nil?
  end

  def dictionary_not_found
    render json: { error: "Could not find the dictionary, #{params[:dictionary_id]}." }, status: :not_found
  end

  def handle_standard_error(exception)
    render json: { error: exception.message }, status: :internal_server_error
  end
end
