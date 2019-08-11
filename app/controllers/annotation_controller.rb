class AnnotationController < ApplicationController

  # GET / POST
  def text_annotation
    @dictionary_names_all = Dictionary.order(:name).pluck(:name)
    dictionaries_selected = Dictionary.find_dictionaries_from_params(params)
    @dictionary_names_selected = dictionaries_selected.map{|d| d.name}

    text = get_text_from_params
    if text.present?
      raise ArgumentError, "At least one dictionary has to be specified for annotation." unless dictionaries_selected.present?
      @result = annotate(text, dictionaries_selected)
    end

    respond_to do |format|
      format.html
      format.json do
        raise ArgumentError, "no text was supplied." unless text.present?
        render json: @result
      end
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

  # POST
  def annotation_request
    raise RuntimeError, "The queue of annotation tasks is full" unless Job.number_of_tasks_to_go(:annotation) < 8

    targets = get_targets_from_json_body
    raise ArgumentError, "No text was supplied." unless targets.present?

    result_name = TextAnnotator::BatchResult.new.name
    delayed_job = enqueue_job(targets, result_name)
    time_for_annotation = calc_time_for_annotation(targets)
    Job.create({name:"Text annotation", dictionary_id:nil, delayed_job_id:delayed_job.id, time: time_for_annotation})

    respond_to do |format|
      retry_after = calc_retry_after(time_for_annotation)
      format.any {head :see_other, location: annotation_result_url(result_name), retry_after: retry_after}
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

  # get
  def annotation_result
    result = TextAnnotator::BatchResult.new(params[:filename])

    case result.status
    when :not_found
      head :gone
    when :queued
      head :not_found
    when :success
      send_file result.file_path, type: :json
    when :error
      send_file result.file_path, type: :json, status: :internal_server_error
    end
  end

  private

  def annotate(text, dictionaries_selected)
    options = get_options_from_params
    annotator = TextAnnotator.new(dictionaries_selected, options[:tokens_len_max], options[:threshold], options[:superfluous], options[:verbose])
    r = annotator.annotate_batch([{text: text}])
    annotator.dispose
    r.first
  end

  def enqueue_job(targets, result_name)
    dictionaries = Dictionary.find_dictionaries_from_params(params)
    options = get_options_from_params

    # job = TextAnnotationJob.new(targets, result_name, dictionaries, options)
    # job.perform()

    Delayed::Job.enqueue TextAnnotationJob.new(targets, result_name, dictionaries, options), queue: :annotation
  end

  def calc_time_for_annotation(targets)
    @time_for_annotation ||= begin
                               # texts may contain a text block or an array of text blocks
      texts = targets.class == Hash ? targets[:text] : targets.map {|t| t[:text]}
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

  def get_targets_from_json_body
    if body.present?
      JSON.parse body, symbolize_names: true
    end
  end

  def get_options_from_params
    options = {}
    options[:tokens_len_max] = tokens_len
    options[:threshold] = threshold
    options[:superfluous] = superfluous
    options[:verbose] = verbose
    options
  end

  def body
    @body ||= request.body.read.force_encoding('UTF-8')
  end

  def threshold
    params[:threshold].to_f if params[:threshold].present?
  end

  def tokens_len
    params[:tokens_len_max].to_i if params[:tokens_len_max].present?
  end

  def superfluous
    true if params[:superfluous] == 'true' || params[:superfluous] == '1'
  end

  def verbose
    true if params[:verbose] == 'true' || params[:verbose] == '1'
  end
end
