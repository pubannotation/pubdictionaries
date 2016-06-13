require 'set'
require 'pathname'
require 'fileutils'
require 'pp'

class DictionariesController < ApplicationController
  # Require authentication for all actions except :index, :show, and some others.
  before_filter :authenticate_user!, except: [ 
    :index, :show,
    :find_ids, :text_annotation,
  ]

  # Disable CSRF check for REST-API actions.
  skip_before_filter :verify_authenticity_token, :only => [
    :text_annotation_with_multiple_dic, :text_annotation_with_single_dic, :id_mapping, :label_mapping
  ], :if => Proc.new { |c| c.request.format == 'application/json' }

  autocomplete :expression, :words

  ###########################
  #####     ACTIONS     #####
  ###########################

  def index
    @dictionaries_grid = initialize_grid(Dictionary.active.accessible(current_user),
      :order => 'created_at',
      :order_direction => 'desc',
      :per_page => 10
    )

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: dics }
    end
  end

  def show
    begin
      @dictionary = Dictionary.active.accessible(current_user).find_by_name(params[:id])
      raise ArgumentError, "Unknown dictionary" if @dictionary.nil?

      if params[:label_search]
        @labels = Label.search_as_text(params[:label_search], @dictionary, params[:page]).records
        @entries = @labels.inject([]){|s, label| s + label.entries}
      elsif params[:id_search]
        @identifier = @dictionary.identifiers.find_by_value(params[:id_search])
        @entries = @identifier.entries.inject([]){|s, e| e.dictionaries.include?(@dictionary) ? s << e : s}
      else
        @entries = @dictionary.entries.page(params[:page]) if @dictionary.present?
      end

      respond_to do |format|
        format.html
        format.json { send_data @dictionary.entries.to_json, filename: "#{@dictionary.name}.json", type: :json }
        format.tsv  { send_data @dictionary.entries.as_tsv,  filename: "#{@dictionary.name}.tsv",  type: :tsv  }
      end
    rescue => e
      respond_to do |format|
        format.html { redirect_to dictionaries_url, notice: e.message }
        format.json { head :unprocessable_entity }
        format.tsv  { head :unprocessable_entity }
      end
    end
  end

  def new
    @dictionary = Dictionary.new
    @dictionary.creator = current_user.email     # set the creator with the user name (email)
    @submit_text = 'Create'

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @dictionary }
    end
  end

  def create
    @dictionary = current_user.dictionaries.new(params[:dictionary])
    @dictionary.name.strip!
    @dictionary.user = current_user

    respond_to do |format|
      if @dictionary.save
        format.html { redirect_to dictionaries_path, notice: 'Empty dictionary created.'}
      else
        format.html { render action: "new" }
      end
    end
  end

  def edit
    @dictionary = Dictionary.editable(current_user).find_by_name(params[:id])
    raise ArgumentError, "Cannot find the dictionary" if @dictionary.nil?
    @submit_text = 'Update'
  end
  
  def update
    @dictionary = Dictionary.editable(current_user).find_by_name(params[:id])
    raise ArgumentError, "Cannot find the dictionary" if @dictionary.nil?

    @dictionary.update_attributes(params[:dictionary])
    if params[:dictionary][:file].present?
      flash[:notice] = 'Creating a dictionary in the background...' 
      @dictionary.cleanup
      run_create_as_a_delayed_job(@dictionary, params)        
    end

    redirect_to dictionary_path(@dictionary)
  end

  def clone
    begin
      dictionary = Dictionary.active.editable(current_user).find_by_name(params[:dictionary_id])
      raise ArgumentError, "Cannot find the dictionary, #{params[:dictionary_id]}, in your management." if dictionary.nil?

      raise ArgumentError, "A source dictionary should be specified." if params[:source_dictionary].nil?
      source_dictionary = Dictionary.active.accessible(current_user).find_by_name(params[:source_dictionary])
      raise ArgumentError, "Cannot find the dictionary, #{params[:dictionary_id]}." if source_dictionary.nil?
      raise ArgumentError, "You cannot clone from itself." if source_dictionary == dictionary

      delayed_job = Delayed::Job.enqueue CloneDictionaryJob.new(source_dictionary, dictionary), queue: :general
      Job.create({name:"Clone dictionary", dictionary_id:dictionary.id, delayed_job_id:delayed_job.id})

      respond_to do |format|
        format.html {redirect_to :back}
      end
    rescue => e
      respond_to do |format|
        format.html {redirect_to :back, notice: e.message}
      end
    end
  end

  def destroy
    begin
      dictionary = Dictionary.editable(current_user).find_by_name(params[:id])
      raise ArgumentError, "Cannot find the dictionary" if dictionary.nil?
      raise RuntimeError, "The last task is not yet dismissed. Please dismiss it and try again." if dictionary.jobs.count > 0

      dictionary.update_attribute(:active, false)
      delayed_job = Delayed::Job.enqueue DestroyDictionaryJob.new(dictionary), queue: :general
      Job.create({name:"Destroy dictionary", dictionary_id:dictionary.id, delayed_job_id:delayed_job.id})

      respond_to do |format|
        format.html {redirect_to dictionaries_path, notice: "The dictionary, #{dictionary.name}, is deleted."}
        format.json {head :no_content}
      end
    rescue => e
      respond_to do |format|
        format.html {redirect_to :back, notice: e.message}
        format.json {head :no_content}
      end
    end
  end

  def find_ids
    redirect_to find_ids_path(dictionaries: params[:id])
  end

  def text_annotation
    redirect_to text_annotation_path(dictionaries: params[:id])
  end
end
