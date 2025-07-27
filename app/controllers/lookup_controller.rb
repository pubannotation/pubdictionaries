require 'fileutils'
require 'csv'

class LookupController < ApplicationController
  include ParameterParsing

  def find_ids_api
    permitted = parse_params_for_find_ids_api

    dictionaries = Dictionary.find_dictionaries(permitted[:dictionaries])
    raise ArgumentError, "no valid dictionary was specified." unless dictionaries.present?

    labels = permitted[:labels]
    raise ArgumentError, "no label was supplied." unless labels.present?

    result = Dictionary.find_ids_by_labels(labels, dictionaries)

    respond_to do |format|
      format.any {render plain: result.values.collect{|v| v.first}.to_csv, content_type: 'text/csv'}
    end

  rescue ArgumentError => e
    raise e if Rails.env.development?
    respond_to do |format|
      format.any {render json: {message:e.message}, status: :bad_request}
    end
  rescue => e
    raise e if Rails.env.development?
    respond_to do |format|
      format.any {render json: {message:e.message}, status: :internal_server_error}
    end
  end

  def find_ids
    permitted = parse_params_for_find_ids

    labels = permitted[:labels]
    @dictionaries_selected = Dictionary.find_dictionaries(permitted[:dictionaries])

    @result = if labels.present?
      raise ArgumentError, "At least one dictionary has to be specified for lookup." unless @dictionaries_selected.present?

      search_options = permitted.slice(
        :threshold,
        :superfluous,
        :verbose,
        :use_ngram_similarity,
        :semantic_threshold,
        :tags
      )

      Dictionary.find_ids_by_labels(labels, @dictionaries_selected, search_options)
    else
      {}
    end

    respond_to do |format|
      format.html
      format.json {
        raise ArgumentError, "no label was supplied." unless labels.present?
        render json: @result
      }
    end
  rescue ArgumentError => e
    raise e if Rails.env.development?
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
    permitted = parse_params_for_find_terms

    identifiers = permitted[:identifiers]
    @dictionaries_selected = Dictionary.find_dictionaries(permitted[:dictionaries])

    @result = if identifiers.present?
      raise ArgumentError, "At least one dictionary has to be specified for lookup." unless @dictionaries_selected.present?

      result = Dictionary.find_labels_by_ids(identifiers, @dictionaries_selected)
      permitted[:verbose] ? result : result.transform_values(&:first)
    else
      {}
    end

    respond_to do |format|
      format.html
      format.json {
        raise ArgumentError, "no identifier was supplied." unless identifiers.present?
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

  def parse_params_for_find_ids_api
    permitted = params.permit(:dictionary, :dictionaries, :label, :labels, :tags,
                              :use_ngram_similarity, :threshold, :semantic_threshold)

    parse_labels_in_csv!(permitted)
    parse_dictionaries!(permitted)

    permitted[:use_ngram_similarity] = to_boolean(permitted[:use_ngram_similarity])
    permitted[:threshold] = to_float(permitted[:threshold])
    permitted[:semantic_threshold] = to_float(permitted[:semantic_threshold])

    permitted[:tags] = to_array(permitted[:tags])

    permitted
  end

  def parse_params_for_find_ids
    permitted = params.permit(:dictionary, :dictionaries, :label, :labels, :tags,
                              :use_ngram_similarity, :threshold,
                              :use_semantic_similarity, :semantic_threshold,
                              :verbose, :superfluous,
                              :commit)

    # Handle text/csv content type
    if request.content_type == 'text/csv' && request.raw_post.present?
      permitted[:labels] = request.raw_post.strip.split(/[\n,]/).map(&:strip).reject(&:blank?)
    else
      parse_labels!(permitted)
    end

    parse_dictionaries!(permitted)

    permitted[:use_ngram_similarity] = to_boolean(permitted[:use_ngram_similarity])
    permitted[:threshold] = to_float(permitted[:threshold])
    permitted[:semantic_threshold] = to_float(permitted[:semantic_threshold])

    permitted[:tags] = to_array(permitted[:tags])

    permitted[:superfluous] = to_boolean(permitted[:superfluous])
    permitted[:verbose] = to_boolean(permitted[:verbose])

    permitted
  end

  def parse_params_for_find_terms
    permitted = params.permit(:dictionary, :dictionaries, :identifier, :identifiers, :verbose, :commit)

    # Handle text/csv content type
    if request.content_type == 'text/csv' && request.raw_post.present?
      permitted[:identifiers] = request.raw_post.strip.split(/[\n,]/).map(&:strip).reject(&:blank?)
    else
      parse_identifiers!(permitted)
    end

    parse_dictionaries!(permitted)

    permitted[:verbose] = to_boolean(permitted[:verbose])

    permitted
  end
end
