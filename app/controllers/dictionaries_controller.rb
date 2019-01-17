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
    :text_annotation, :id_mapping, :label_mapping
  ], :if => Proc.new { |c| c.request.format == 'application/json' }

  autocomplete :user, :username

  def index
    @dictionaries_grid = initialize_grid(Dictionary,
      :conditions => ["public = ?", true],
      :order => 'created_at',
      :order_direction => 'desc',
      :per_page => 20
    )

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: dics }
    end
  end

  def show
    begin
      @dictionary = Dictionary.find_by_name(params[:id])
      raise ArgumentError, "Unknown dictionary" if @dictionary.nil?

      if params[:label_search]
        @entries = Entry.narrow_by_label(params[:label_search], @dictionary, params[:page])
      elsif params[:id_search]
        @entries = Entry.narrow_by_identifier(params[:id_search], @dictionary).page(params[:page])
      else
        @entries = @dictionary.entries.order("mode DESC").order(:label).page(params[:page]) if @dictionary.present?
      end

      @addition_num = @dictionary.num_addition
      @deletion_num = @dictionary.num_deletion

      respond_to do |format|
        format.html
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
    @dictionary.user = current_user    # set the creator with the user name
    @submit_text = 'Create'

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @dictionary }
    end
  end

  def create
    params[:dictionary][:associated_managers] = [] unless params[:dictionary][:associated_managers].respond_to?(:each)
    params[:dictionary][:languages] = [] unless params[:dictionary][:languages].respond_to?(:each)
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

    associated_managers = if params[:dictionary][:associated_managers]
      _m = params[:dictionary][:associated_managers].split(/,/).map{|u| User.find_by_username(u)}
      params[:dictionary].delete(:associated_managers)
      _m
    end

    languages = if params[:dictionary][:languages]
      _languages = params[:dictionary][:languages].split(/,/).map do |l|
        _l = Language.find_by_abbreviation(l)
        if _l.nil?
          name = I18nData.languages[l]
          raise ArgumentError, "Invalid language selection: #{l}" if name.nil?
          _l = Language.create({abbreviation: l, name:name})
        end
        _l
      end
      params[:dictionary].delete(:languages)
      _languages
    end

    @dictionary.update_attributes(params[:dictionary])

    unless !associated_managers || associated_managers == @dictionary.associated_managers
      to_delete = @dictionary.associated_managers - associated_managers
      to_add = associated_managers - @dictionary.associated_managers
      to_delete.each{|u| @dictionary.associated_managers.destroy(u)}
      to_add.each{|u| @dictionary.associated_managers << u}
    end

    unless !languages || languages == @dictionary.languages
      to_delete = @dictionary.languages - languages
      to_add = languages - @dictionary.languages
      to_delete.each{|u| @dictionary.languages.destroy(u)}
      to_add.each{|u| @dictionary.languages << u}
    end

    redirect_to dictionary_path(@dictionary)
  end

  def clone
    begin
      dictionary = Dictionary.editable(current_user).find_by_name(params[:dictionary_id])
      raise ArgumentError, "Cannot find the dictionary, #{params[:dictionary_id]}, in your management." if dictionary.nil?

      raise ArgumentError, "A source dictionary should be specified." if params[:source_dictionary].nil?
      source_dictionary = Dictionary.find_by_name(params[:source_dictionary])
      raise ArgumentError, "Cannot find the dictionary, #{params[:source_dictionary]}." if source_dictionary.nil?
      raise ArgumentError, "You cannot clone from itself." if source_dictionary == dictionary

      delayed_job = Delayed::Job.enqueue CloneDictionaryJob.new(source_dictionary, dictionary), queue: :upload
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

  def empty
    begin
      dictionary = Dictionary.editable(current_user).find_by_name(params[:dictionary_id])
      raise ArgumentError, "Cannot find the dictionary." if dictionary.nil?

      dictionary.empty_entries

      respond_to do |format|
        format.html{ redirect_to :back }
      end
    rescue => e
      respond_to do |format|
        format.html{ redirect_to :back, notice: e.message }
      end
    end
  end

  def compile
    begin
      dictionary = Dictionary.editable(current_user).find_by_name(params[:id])
      raise ArgumentError, "Cannot find the dictionary" if dictionary.nil?

      delayed_job = Delayed::Job.enqueue CompileJob.new(dictionary), queue: :general
      Job.create({name:"Compile entries", dictionary_id:dictionary.id, delayed_job_id:delayed_job.id})

      respond_to do |format|
        format.html{ redirect_to :back }
      end
    rescue => e
      respond_to do |format|
        format.html {redirect_to dictionary_path(dictionary), notice: e.message}
        format.json {head :no_content}
      end
    end
  end

  def destroy
    begin
      dictionary = Dictionary.administrable(current_user).find_by_name(params[:id])
      raise ArgumentError, "Cannot find the dictionary" if dictionary.nil?
      raise RuntimeError, "The last task is not yet dismissed. Please dismiss it and try again." if dictionary.jobs.count > 0

      dictionary.empty_entries
      dictionary.destroy

      respond_to do |format|
        format.html {redirect_to dictionaries_path, notice: "The dictionary, #{dictionary.name}, is deleted."}
        format.json {head :no_content}
      end
    rescue => e
      respond_to do |format|
        format.html {redirect_to dictionaries_path, notice: e.message}
        format.json {head :no_content}
      end
    end
  end

end
