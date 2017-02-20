require 'fileutils'

class AnnotationController < ApplicationController
  def text_annotation
    begin
      @dictionaries_selected = Dictionary.find_dictionaries_from_params(params)
      @dictionaries = Dictionary.all

      @result = if params[:text].present?
        rich = true if params[:rich] == 'true' || params[:rich] == '1'
        tokens_len_max = params[:tokens_len_max].to_i if params[:tokens_len_max].present?
        threshold = params[:threshold].to_f if params[:threshold].present?
        annotator = TextAnnotator.new(@dictionaries_selected, tokens_len_max, threshold, rich)
        annotator.annotate(params[:text])
      else
        {}
      end

      respond_to do |format|
        format.html
        format.json {
          raise ArgumentError, "no text is supplied." unless params[:text].present?
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

  # post
  def annotation_request
    begin
      dictionaries = Dictionary.find_dictionaries_from_params(params)

      texts = if params.has_key?(:_json)
        params[:_json]
      elsif params.has_key?(:text)
        {text: params[:text]}
      else
        {text: request.body.read}
      end

      texts = [texts] if texts.class == Hash
      raise ArgumentError, "No text is supplied." unless texts.present?

      rich = true if params[:rich] == 'true' || params[:rich] == '1'
      tokens_len_max = params[:tokens_len_max].to_i if params[:tokens_len_max].present?
      threshold = params[:threshold].to_f if params[:threshold].present?
      annotator = TextAnnotator.new(dictionaries, tokens_len_max, threshold, rich)

      filename = "annotation-results-#{SecureRandom.uuid}"
      FileUtils.touch(TextAnnotator::RESULTS_PATH + filename)

      # a = TextAnnotationJob.new(texts, annotator, filename)
      # a.perform()

      Delayed::Job.enqueue TextAnnotationJob.new(texts, annotator, filename), queue: :general

      respond_to do |format|
        format.any {head :see_other, location: annotation_result_path(filename)}
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

  # get
  def annotation_result
    begin
      filename = params[:filename] + '.json'
      filepath = TextAnnotator::RESULTS_PATH + params[:filename]

      if File.exist?(filepath + 'json')
        send_file filepath, filename: filename, type: :json
      elsif File.exist?(filepath)
        head :service_unavailable, retry_after: 10
      else
        head :bad_request
      end
    end
  end
end
