class AnnotationController < ApplicationController
  include ParameterParsing

  skip_before_action :verify_authenticity_token, only: [:annotation_request, :annotation_task]

  # GET / POST
  def text_annotation
    @permitted = parse_params_for_text_annotation

    @dictionaries_selected = Dictionary.find_dictionaries(@permitted[:dictionaries])
    text = @permitted[:text]

    @result = if text.present?
      raise ArgumentError, "At least one dictionary has to be specified for annotation." unless @dictionaries_selected.present?

      options = @permitted.slice(
        :tokens_len_min,
        :tokens_len_max,
        :use_ngram_similarity,
        :semantic_threshold,
        :threshold,
        :longest,
        :superfluous,
        :verbose,
        :no_text,
        :abbreviation,
        :tags
      )

      annotator = if options[:semantic_similarity]
        TextAnnotatorSem.new(@dictionaries_selected, options)
      else
        TextAnnotator.new(@dictionaries_selected, options)
      end
      Rails.logger.debug "About to call annotate_batch"
      r = annotator.annotate_batch([{text: text}]).first
      Rails.logger.debug "Annotate_batch completed"
      Rails.logger.debug "Annotator responds to context_similarities: #{annotator.respond_to?(:context_similarities)}"
      @context_similarities = annotator.context_similarities if annotator.respond_to?(:context_similarities)
      Rails.logger.debug "Context similarities assigned: #{@context_similarities.inspect}"
      annotator.dispose
      r.delete(:text) if options[:no_text]
      r
    end

    respond_to do |format|
      format.html
      format.json do
        raise ArgumentError, "no text was supplied." unless text.present?
        render json: @result
      end
    end
  rescue ArgumentError => e
    raise e if Rails.env.development?
    respond_to do |format|
      format.html {flash.now[:notice] = e.message}
      format.any  {render json: {message:e.message}, status: :bad_request}
    end
  rescue => e
    raise e if Rails.env.development?
    respond_to do |format|
      format.html {flash.now[:notice] = e.message}
      format.any {render json: {message:e.message}, status: :internal_server_error}
    end
  end

  # POST
  def annotation_request
    targets = get_targets_from_json_body
    raise ArgumentError, "No text was supplied." unless targets.present?
    raise TextAnnotator::AnnotationQueueOverflowError unless Job.number_of_tasks_to_go(:annotation) < 8

    time_for_annotation = calc_time_for_annotation(targets)
    callback_url = request.headers['HTTP_ANNOTATION_RECEPTION_CALLBACK_URL']
    job = enqueue_job(targets, targets.length, time_for_annotation, callback_url)

    respond_to do |format|
      format.any {head :ok}
    end
  rescue ArgumentError => e
    respond_to do |format|
      format.any {render json: {message:e.message}, status: :bad_request}
    end
  rescue TextAnnotator::AnnotationQueueOverflowError => e
    respond_to do |format|
      format.any {render json: {message:"The annotation queue is full"}, status: :service_unavailable}
    end
  rescue => e
    respond_to do |format|
      format.any {render json: {message:e.message}, status: :internal_server_error}
    end
  end

  # POST
  def annotation_task
    target = get_target

    raise ArgumentError, "No text was supplied." unless target.present?
    raise TextAnnotator::AnnotationQueueOverflowError unless Job.number_of_tasks_to_go(:annotation) < 8

    time_for_annotation = calc_time_for_annotation(target)
    num_items = target.class == Array ? target.length : 1
    job = enqueue_job(target, num_items, time_for_annotation)

    respond_to do |format|
      format.any  {render json: job.description(request.host_with_port), status: :created, location: annotation_task_show_url(job), content_type: 'application/json'}
      format.csv  {send_data job.description_csv(request.host_with_port), type: :csv, dispotition: :inline, status: :created, location: annotation_task_show_url(job), content_type: 'text/csv'}
      format.tsv  {send_data job.description_csv(request.host_with_port), type: :csv, dispotition: :inline, status: :created, location: annotation_task_show_url(job), content_type: 'text/csv'}
      format.json {render json: job.description(request.host_with_port), status: :created, location: annotation_task_show_url(job)}
    end

  rescue ArgumentError => e
    respond_to do |format|
      format.any {render json: {message:e.message}, status: :bad_request}
    end
  rescue TextAnnotator::AnnotationQueueOverflowError => e
    respond_to do |format|
      format.any {render json: {message:"The annotation queue is full"}, status: :service_unavailable}
    end
  rescue => e
    respond_to do |format|
      format.any {render json: {message:e.message}, status: :internal_server_error}
    end
  end

  # get
  def annotation_result
    result = TextAnnotator::BatchResult.new(filename)

    case result.status
    when :not_found
      job = Job.find(result.job_id)
      if job
        case job.status
        when :in_queue, :in_progress
          head :not_found, retry_after: job.etr
        when :done
          head :gone
        end
      else
        head :gone
      end
    when :success
      job = Job.find(result.job_id)
      job.destroy_if_not_running
      send_file result.file_path, type: :json
    when :error
      send_file result.file_path, type: :json, status: :internal_server_error
    end
  end

  private

  def filename
    fn = params[:filename]
    fn += '.' + params[:format]  if params[:format]
    fn
  end

  def enqueue_job(target, num_items, time_for_annotation, callback_url = nil)
    dictionaries = Dictionary.find_dictionaries_from_params(params)
    options = get_options_from_params

    # job = TextAnnotationJob.new(target, dictionaries, options)
    # job.perform()
    active_job = TextAnnotationJob.perform_later(target, dictionaries, options, callback_url)
    active_job.create_job_record("Text annotation", num_items, time_for_annotation)
  end

  def calc_time_for_annotation(target)
    @time_for_annotation ||= begin
                               # texts may contain a text block or an array of text blocks
      texts = target.class == Hash ? target[:text] : target.map {|t| t[:text]}
      TextAnnotator.time_estimation(texts)
    end
  end

  def calc_retry_after(time_for_annotation)
    number_of_annotation_workers = 4
    time_for_queue = Job.time_for_tasks_to_go(:annotation) / number_of_annotation_workers
    time_for_queue + time_for_annotation
  end

  def get_text_from_params
    if params[:text].present?
      params[:text]
    else
      if body.present?
        begin
          r = JSON.parse body, symbolize_names: true
          r[:text]
        rescue
          body
        end
      end
    end
  end

  def get_target
    content_type = request.content_type.downcase
    if content_type =~ /json/
      parsed = JSON.parse body, symbolize_names: true
      raise ArgumentError, "No text was supplied." if (parsed.class == Array && parsed[0][:text].nil?) || (parsed.class == Hash && parsed[:text].nil?)
      parsed
    elsif content_type =~ /text/
      {text: body}
    elsif content_type =~ /form-urlencoded/
      {text: params[:text]}
    elsif content_type =~ /form-data/
      {text: params[:text]}
    end
  end

  def get_targets_from_body
    if body.present?
      JSON.parse body, symbolize_names: true
    end
  end

  def get_targets_from_json_body
    if body.present?
      JSON.parse body, symbolize_names: true
    end
  end

  def get_targets_from_params
    if params[:texts].present?
      texts = params[:texts]
      if texts.respond_to? :each
        texts
      else
        JSON.parse texts, symbolize_names: true
      end
    end
  end

  def get_options_from_params
    options = {}

    options[:tokens_len_min] = get_option_integer(:tokens_len_min)
    options[:tokens_len_max] = get_option_integer(:tokens_len_max)
    options[:threshold] = get_option_float(:threshold)
    options[:semantic_threshold] = get_option_float(:semantic_threshold)

    [:longest, :superfluous, :verbose, :no_text, :abbreviation, :use_ngram_similarity].each do |key|
      options[key] = if (params[:commit] != 'Submit') && TextAnnotator::OPTIONS_DEFAULT[key]
        params[key] != 'false'
      else
        get_option_boolean(key)
      end
    end

    options
  end

  def body
    @body ||= request.body.read.force_encoding('UTF-8')
  end

  def get_option_float(key)
    params[key].present? ? params[key].to_f : nil
  end

  def get_option_integer(key)
    params[key].present? ? params[key].to_i : nil
  end

  def get_option_boolean(key)
    (params[key] == 'true' || params[key] == '1') ? true : false
  end

  def parse_params_for_text_annotation
    permitted = params.permit(:dictionary, :dictionaries, :text, :tags,
                              :tokens_len_min, :tokens_len_max,
                              :use_ngram_similarity, :threshold,
                              :use_semantic_similarity, :semantic_threshold,
                              :longest, :verbose, :superfluous, :no_text, :abbreviation,
                              :commit)

    parse_dictionaries!(permitted)

    permitted[:tokens_len_min] = to_integer(permitted[:tokens_len_min])
    permitted[:tokens_len_max] = to_integer(permitted[:tokens_len_max])

    permitted[:threshold] = to_float(permitted[:threshold])
    permitted[:semantic_threshold] = to_float(permitted[:semantic_threshold])

    permitted[:longest] = to_boolean(permitted[:longest])
    permitted[:superfluous] = to_boolean(permitted[:superfluous])
    permitted[:verbose] = to_boolean(permitted[:verbose])
    permitted[:no_text] = to_boolean(permitted[:no_text])
    permitted[:abbreviation] = to_boolean(permitted[:abbreviation])
    permitted[:use_ngram_similarity] = to_boolean(permitted[:use_ngram_similarity])

    permitted[:tags] = to_array(permitted[:tags])

    permitted
  end
end
