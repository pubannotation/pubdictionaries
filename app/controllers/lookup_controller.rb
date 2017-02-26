require 'fileutils'

class LookupController < ApplicationController
  def find_ids
    begin
      @dictionaries_selected = Dictionary.find_dictionaries_from_params(params)
      @dictionaries = Dictionary.all

      params[:labels] = params[:label] if params.has_key?(:label) && !params.has_key?(:labels)
      labels = if params[:labels]
        params[:labels].strip.split(/[\n\t\r|]+/)
      elsif params[:_json]
        params[:_json]
      end

      @result = if labels.present?
        rich = true if params[:rich] == 'true' || params[:rich] == '1'
        threshold = params[:threshold].present? ? params[:threshold].to_f : 0.85
        @result = Dictionary.find_ids_by_labels(labels, @dictionaries_selected, threshold, rich)
      else
        {}
      end

      respond_to do |format|
        format.html
        format.json {
          raise ArgumentError, "no label was supplied." unless labels.present?
          render json:@result
        }
      end
    rescue ArgumentError => e
      respond_to do |format|
        format.any {render json: {message:e.message}, status: :bad_request}
      end
    rescue => e
      respond_to do |format|
        format.any {render json: {message:e.message}, status: :internal_server_error}
      end
    end
  end

  def prefix_completion
    begin
      dictionary = Dictionary.find_by_name(params[:id])
      raise ArgumentError, "Unknown dictionary" if dictionary.nil?

      entries = if params[:term]
        Entry.narrow_by_label_prefix(params[:term], dictionary)
      end

      respond_to do |format|
        format.any {render json:entries}
      end
    rescue ArgumentError => e
      respond_to do |format|
        format.any {render json: {message:e.message}, status: :bad_request}
      end
    rescue => e
      respond_to do |format|
        format.any {render json: {notice:e.message}, status: :internal_server_error}
      end
    end
  end

  def substring_completion
    begin
      dictionary = Dictionary.find_by_name(params[:id])
      raise ArgumentError, "Unknown dictionary" if dictionary.nil?

      entries = if params[:term]
        Entry.narrow_by_label(params[:term], dictionary)
      end

      respond_to do |format|
        format.any {render json:entries}
      end
    rescue ArgumentError => e
      respond_to do |format|
        format.any {render json: {message:e.message}, status: :bad_request}
      end
    rescue => e
      respond_to do |format|
        format.any {render json: {notice:e.message}, status: :unprocessable_entity}
      end
    end
  end


  def call_ws
    rest_url = params[:rest_url]
    delimiter = params[:delimiter]
    labels = params[:labels]
    method = 1

    response = begin
      if method == 0
        RestClient.get rest_url, {:params => call_params, :accept => :json}
      else
        RestClient.post rest_url, labels.split(delimiter).to_json, :content_type => :json, :accept => :json
      end
    rescue => e
      raise IOError, "Invalid connection"
    end

    raise IOError, "Bad gateway" unless response.code == 200

    begin
      result = JSON.parse response, :symbolize_names => true
    rescue => e
      raise IOError, "Received a non-JSON object: [#{response}]"
    end

    render :find_ids
  end
end
