class AnnotationController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:annotation_task]

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
    targets = get_targets_from_json_body
    raise ArgumentError, "No text was supplied." unless targets.present?
    raise AnnotationQueueOverflowError unless Job.number_of_tasks_to_go(:annotation) < 8

    delayed_job = enqueue_job(targets)
    time_for_annotation = calc_time_for_annotation(targets)
    job = Job.create({name:"Text annotation", dictionary_id:nil, delayed_job_id:delayed_job.id, num_items:targets.length, time: time_for_annotation, registered_at:delayed_job.created_at})
    result_name = TextAnnotator::BatchResult.new(nil, job.id).filename

    respond_to do |format|
      format.any {head :see_other, location: annotation_result_url(result_name), retry_after: time_for_annotation}
    end
  rescue ArgumentError => e
    respond_to do |format|
      format.any {render json: {message:e.message}, status: :bad_request}
    end
  rescue AnnotationQueueOverflowError => e
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
    raise AnnotationQueueOverflowError unless Job.number_of_tasks_to_go(:annotation) < 8

    delayed_job = enqueue_job(target)
    time_for_annotation = calc_time_for_annotation(target)
    num_items = target.class == Array ? target.length : 1
    job = Job.create({name:"Text annotation", dictionary_id:nil, delayed_job_id:delayed_job.id, num_items:num_items, time: time_for_annotation, registered_at:delayed_job.created_at})

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
  rescue AnnotationQueueOverflowError => e
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
      send_file result.file_path, type: :json
    when :error
      send_file result.file_path, type: :json, status: :internal_server_error
    end
  end

  # POST
  def annotation_job
    targets = get_targets_from_params
    raise ArgumentError, "No text was supplied." unless targets.present?

    raise RuntimeError, "The queue of annotation tasks is full" unless Job.number_of_tasks_to_go(:annotation) < 50

    result_name = TextAnnotator::BatchResult.new.name
    delayed_job = enqueue_job(targets, result_name)
    etr = calc_time_for_annotation(targets)
    job = Job.create({name:"Text annotation", dictionary_id:nil, delayed_job_id:delayed_job.id, time: etr})

    respond_to do |format|
      # retry_after = calc_retry_after(time_for_annotation)
      format.any  {send_data job.description_csv, type: :csv, dispotition: :inline, status: :created, location: job_url(job) }
      format.csv  {send_data job.description_csv, type: :csv, dispotition: :inline, status: :created, location: job_url(job) }
      format.json {render json: job.description, status: :created, location: job_url(job)}
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

  private

  def filename
    fn = params[:filename]
    fn += '.' + params[:format]  if params[:format]
    fn
  end

  def annotate(text, dictionaries_selected)
    options = get_options_from_params

    annotator = TextAnnotator.new(dictionaries_selected, options)
    r = annotator.annotate_batch([{text: text}]).first
    annotator.dispose
    r.delete(:text) if options[:no_text]
    r
  end

  def enqueue_job(target)
    dictionaries = Dictionary.find_dictionaries_from_params(params)
    options = get_options_from_params

    # job = TextAnnotationJob.new(target, dictionaries, options)
    # job.perform()

    Delayed::Job.enqueue TextAnnotationJob.new(target, dictionaries, options), queue: :annotation
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
    options[:abbreviation] = get_option_boolean(:abbreviation)
    options[:longest] = get_option_boolean(:longest)
    options[:superfluous] = get_option_boolean(:superfluous)
    options[:verbose] = get_option_boolean(:verbose)
    options[:no_text] = get_option_boolean(:no_text)
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
end
