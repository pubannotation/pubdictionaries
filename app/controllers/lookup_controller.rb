require 'fileutils'
require 'csv'

class LookupController < ApplicationController
  def find_ids_api
    dictionary = Dictionary.find_by name:params[:dictionary]
    labels = params[:labels].parse_csv
    result = Dictionary.find_ids_by_labels(labels, [dictionary])

    respond_to do |format|
      format.any {render plain: result.values.collect{|v| v.first}.to_csv, content_type: 'text/csv'}
    end
  end

  def find_ids
    dictionaries_selected = Dictionary.find_dictionaries_from_params(params)
    params[:labels] = params[:label] if params.has_key?(:label) && !params.has_key?(:labels)
    labels = if params[:labels]
      get_values(params[:labels])
    elsif params[:_json]
      params[:_json]
    else
      body = request.body.read.force_encoding('UTF-8')
      get_values(body) if body.present?
    end

    @dictionary_names_all = Dictionary.order(:name).pluck(:name)
    @dictionary_names_selected = dictionaries_selected.map{|d| d.name}

    @result = if labels.present?
      raise ArgumentError, "At least one dictionary has to be specified for lookup." unless dictionaries_selected.present?
      threshold = params[:threshold].present? ? params[:threshold].to_f : nil
      superfluous = get_option_boolean(:superfluous)
      verbose = get_option_boolean(:verbose)
      ngram = if (params[:commit] == 'Submit')
        get_option_boolean(:ngram)
      else
        params[:ngram] != 'false'
      end
      tags = params[:tags].present? ? get_values(params[:tags]) : []
      @result = Dictionary.find_ids_by_labels(labels, dictionaries_selected, threshold, superfluous, verbose, ngram, tags)
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
    raise e if Rails.env.development?
    respond_to do |format|
      format.html {flash.now[:notice] = e.message}
      format.any {render json: {message:e.message}, status: :internal_server_error}
    end
  end

  def find_terms
    begin
      dictionaries_selected = Dictionary.find_dictionaries_from_params(params)
      ids = if params[:ids]
        get_values(params[:ids])
      elsif params[:_json]
        params[:_json]
      else
        body = request.body.read.force_encoding('UTF-8')
        get_values(body) if body.present?
      end

      @dictionary_names_all = Dictionary.order(:name).pluck(:name)
      @dictionary_names_selected = dictionaries_selected.map{|d| d.name}

      @result = if ids.present?
        raise ArgumentError, "At least one dictionary has to be specified for lookup." unless dictionaries_selected.present?
        verbose = get_option_boolean(:verbose)
        result = Dictionary.find_labels_by_ids(ids, dictionaries_selected)
        verbose ? result : result.transform_values(&:first)
      else
        {}
      end

      respond_to do |format|
        format.html
        format.json {
          raise ArgumentError, "no id was supplied." unless ids.present?
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
      raise ArgumentError, "Unknown dictionary: #{params[:id]}." if dictionary.nil?

      entries = if params[:term]
        page = params[:page] || 0
        dictionary.entries.narrow_by_label_prefix(params[:term], page, params[:per_page])
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
      raise ArgumentError, "Unknown dictionary: #{params[:id]}." if dictionary.nil?

      entries = if params[:term]
        page = params[:page] || 0
        dictionary.entries.narrow_by_label(params[:term], page, params[:per_page])
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

  def mixed_completion
    begin
      dictionary = Dictionary.find_by_name(params[:id])
      raise ArgumentError, "Unknown dictionary: #{params[:id]}." if dictionary.nil?

      entries = if params[:term]
        page = params[:page] || 0
        dictionary.entries.narrow_by_label_prefix_and_substring(params[:term], page, params[:per_page])
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

  private

  def get_option_boolean(key)
    (params[key] == 'true' || params[key] == '1') ? true : false
  end

  def get_values(symbol_separated_values)
    symbol_separated_values.strip.split(/[\n\t\r|,]+/).map(&:strip)
  end

end
