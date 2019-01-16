require 'fileutils'
require 'json'

class AnnotationController < ApplicationController

  # GET
  def text_annotation
    begin
      dictionaries_selected = Dictionary.find_dictionaries_from_params(params)
      text =
        if params[:text].present?
          params[:text]
        else
          body = request.body.read.force_encoding('UTF-8')
          if body.present?
            begin
              r = JSON.parse body, symbolize_names: true
              r[:text]
            rescue
              body
            end
          end
        end

      @dicnames_all = Dictionary.order(:name).pluck(:name)
      @dicnames_sel = dictionaries_selected.map{|d| d.name}

      @result = if text.present?
        raise ArgumentError, "At least one dictionary has to be specified for annotation." unless dictionaries_selected.present?
        rich = true if params[:rich] == 'true' || params[:rich] == '1'
        tokens_len_max = params[:tokens_len_max].to_i if params[:tokens_len_max].present?
        threshold = params[:threshold].to_f if params[:threshold].present?
        annotator = TextAnnotator.new(dictionaries_selected, tokens_len_max, threshold, rich)
        r = annotator.annotate_batch([{text:text}])
        annotator.done
        r.first
      else
        {}
      end

      respond_to do |format|
        format.html
        format.json {
          raise ArgumentError, "no text was supplied." unless text.present?
          render json:@result
        }
      end
    rescue ArgumentError => e
      respond_to do |format|
        format.html {flash.now[:notice] = e.message}
        format.any  {render json: {message:e.message}, status: :bad_request}
      end
    rescue => e
      respond_to do |format|
        format.html {flash.now[:notice] = e.message}
        format.any {render json: {message:e.message}, status: :internal_server_error}
      end
    end
  end

  # POST
  def annotation_request
    begin
      dictionaries = Dictionary.find_dictionaries_from_params(params)

      body = request.body.read.force_encoding('UTF-8')

      target = if body.present?
        JSON.parse body, symbolize_names: true
      end

      raise ArgumentError, "No text was supplied." unless target.present?
      raise RuntimeError, "The queue of annotation tasks is full" unless Job.number_of_tasks_to_go(:annotation) < 8

      options = {}
      options[:rich] = true if params[:rich] == 'true' || params[:rich] == '1'
      options[:tokens_len_max] = params[:tokens_len_max].to_i if params[:tokens_len_max].present?
      options[:threshold] = params[:threshold].to_f if params[:threshold].present?

      # Set up directory
      TextAnnotator::Result.setup_directory

      filename = "annotation-result-#{SecureRandom.uuid}"
      FileUtils.touch(TextAnnotator::RESULTS_PATH + filename)

      number_of_annotation_workers = 4
      time_for_queue = Job.time_for_tasks_to_go(:annotation) / number_of_annotation_workers

      # texts may contain a text block or an array of text blocks
      texts = target.class == Hash ? target[:text] : target.map{|t| t[:text]}
      time_for_annotation = TextAnnotator.time_estimation(texts)

      delayed_job = Delayed::Job.enqueue TextAnnotationJob.new(target, filename, dictionaries, options), queue: :annotation
      Job.create({name:"Text annotation", dictionary_id:nil, delayed_job_id:delayed_job.id, time: time_for_annotation})

      respond_to do |format|
        format.any {head :see_other, location: annotation_result_url(filename), retry_after: time_for_queue + time_for_annotation}
      end
    rescue ArgumentError => e
      respond_to do |format|
        format.any {render json: {message:e.message}, status: :bad_request}
      end
    rescue RuntimeError => e
      respond_to do |format|
        format.any {render json: {message:e.message}, status: :service_unavailable}
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
      filepath = TextAnnotator::RESULTS_PATH + filename

      if File.exist?(filepath)
        annotations = JSON.parse(File.read(filepath), symbolize_names: true)

        success = if annotations.class == Array
          annotations.first.has_key?(:text)
        else
          annotations.has_key?(:text)
        end

        if success
          send_file filepath, filename: filename, type: :json
        else
          send_file filepath, filename: filename, type: :json, status: :internal_server_error
        end
      elsif File.exist?(TextAnnotator::RESULTS_PATH + params[:filename])
        head :not_found
      else
        head :gone
      end
    end
  end
end
