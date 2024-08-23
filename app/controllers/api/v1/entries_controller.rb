class Api::V1::EntriesController < ApplicationController
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
        entry = dictionary.new_entry(label, identifier, nil, EntryMode::WHITE, true)

        tag_ids = params[:tags] || []
        entry.tag_ids = tag_ids

        if entry.save
          dictionary.update_entries_num

          render json: { message: "The white entry #{entry} was created." }, status: :created
        else
          render json: { message: "The white entry #{entry} could not be created." }, status: :unprocessable_entity
        end
      end
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end
  end
end
