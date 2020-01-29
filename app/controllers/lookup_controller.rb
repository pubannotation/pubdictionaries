require 'fileutils'

class LookupController < ApplicationController
  def find_ids
    begin
      dictionaries_selected = Dictionary.find_dictionaries_from_params(params)
      params[:labels] = params[:label] if params.has_key?(:label) && !params.has_key?(:labels)
      labels = if params[:labels]
        params[:labels].strip.split(/[\n\t\r|]+/)
      elsif params[:_json]
        params[:_json]
      else
        body = request.body.read.force_encoding('UTF-8')
        body.strip.split(/[\n\t\r|]+/) if body.present?
      end

      @dictionary_names_all = Dictionary.order(:name).pluck(:name)
      @dictionary_names_selected = dictionaries_selected.map{|d| d.name}

      @result = if labels.present?
        raise ArgumentError, "At least one dictionary has to be specified for lookup." unless dictionaries_selected.present?
        superfluous = true if params[:superfluous] == 'true' || params[:superfluous] == '1'
        verbose = true if params[:verbose] == 'true' || params[:verbose] == '1'
        threshold = params[:threshold].present? ? params[:threshold].to_f : 0.85
        @result = Dictionary.find_ids_by_labels(labels, dictionaries_selected, threshold, superfluous, verbose)
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
        format.html {flash.now[:notice] = e.message}
        format.any {render json: {message:e.message}, status: :bad_request}
      end
    rescue => e
      respond_to do |format|
        format.html {flash.now[:notice] = e.message}
        format.any {render json: {message:e.message}, status: :internal_server_error}
      end
    end
  end

  def prefix_completion
    begin
      dictionary = Dictionary.find_by_name(params[:id])
      raise ArgumentError, "Unknown dictionary" if dictionary.nil?

      entries = if params[:term]
        dictionary.narrow_entries_by_label_prefix(params[:term])
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
        dictionary.narrow_entries_by_label(params[:term])
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
end
