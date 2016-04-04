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
      @dictionary = Dictionary.active.accessible(current_user).find_by_title(params[:id])
      raise ArgumentError, "Unknown dictionary" if @dictionary.nil?

      if params[:label_search]
        @labels = Label.search_as_text(params[:label_search], @dictionary, params[:page]).records
        @entries = @labels.inject([]){|s, label| s + label.entries}
      elsif params[:id_search]
        identifier = @dictionary.identifiers.find_by_value(params[:id_search])
        @entries = identifier.nil? ? [] : identifier.entries.page(params[:page])
      else
        @entries = @dictionary.entries.page(params[:page]) if @dictionary.present?
      end

      respond_to do |format|
        format.html
        format.tsv { 
          send_data tsv_data(@entries), 
          filename: "#{@dictionary.title}.#{params[:query]}.tsv", 
          type:     "text/tsv" 
        }
      end
    rescue => e
      respond_to do |format|
        format.html {redirect_to dictionaries_url, notice: e.message}
        format.tsv {}
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
    dictionary = current_user.dictionaries.new(params[:dictionary])
    dictionary.title.strip!
    dictionary.user = current_user

    respond_to do |format|
      if dictionary.save
        format.html {redirect_to dictionaries_url, notice: 'Empty dictionary created.'}
      else
        format.html {redirect_to dictionaries_url, notice: 'Creation of a dictionary failed.'}
      end
    end
  end

  def edit
    @dictionary = Dictionary.find_showable_by_title( params[:id], current_user )
    @submit_text = 'Update'
  end
  
  def update
    @dictionary = Dictionary.find_showable_by_title( params[:id], current_user )
    @dictionary.update_attributes(params[:dictionary])
    if params[:dictionary][:file].present?
      flash[:notice] = 'Creating a dictionary in the background...' 
      @dictionary.cleanup
      run_create_as_a_delayed_job(@dictionary, params)        
    end

    redirect_to dictionaries_path(dictionary_type: 'my_dic')
  end

  def destroy
    begin
      dictionary = Dictionary.editable(current_user).find_by_title(params[:id])
      raise ArgumentError, "Cannot find the dictionary" if dictionary.nil?
      raise RuntimeError, "The last task is not yet dismissed. Please dismiss it and try again." if dictionary.jobs.count > 0

      dictionary.update_attribute(:active, false)
      delayed_job = Delayed::Job.enqueue DestroyDictionaryJob.new(dictionary), queue: :general
      Job.create({name:"Destroy dictionary", dictionary_id:dictionary.id, delayed_job_id:delayed_job.id})

      respond_to do |format|
        format.html {redirect_to dictionaries_path, notice: "The dictionary, #{dictionary.title}, is deleted."}
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
