require 'set'
require 'pathname'
require 'fileutils'
require 'pp'

class DictionariesController < ApplicationController
  # Require authentication for all actions except :index, :show, and some others.
  before_action :authenticate_user!, except: [
    :index, :show, :show_patterns,
    :find_ids, :text_annotation,
    :downloadable, :create_downloadable
  ]

  # Disable CSRF check for REST-API actions.
  skip_before_action :verify_authenticity_token, :only => [
    :text_annotation, :id_mapping, :label_mapping, :create
  ], :if => Proc.new { |c| c.request.format == 'application/json' }

  autocomplete :user, :username

  def index
    @dictionaries_grid = initialize_grid(Dictionary,
      :conditions => ["public = ?", true],
      :order => 'created_at',
      :order_direction => 'desc',
      :per_page => 20
    )

    dics = Dictionary.index_dictionaries
    respond_to do |format|
      format.html # index.html.erb
      format.json do
        render json: dics.as_json(only: [:name, :entries_num], methods: [:maintainer, :dic_created_at])
      end
    end
  end

  def show
    @dictionary = Dictionary.find_by!(name: params[:id])

    respond_to do |format|
      page = (params[:page].presence || 1).to_i
      per  = (params[:per].presence || 15).to_i
      entries_with_tags = @dictionary.entries.includes(:tags)

      format.html {
        @entries, @type_entries = if params[:label_search]
          params[:label_search].strip!
          [entries_with_tags.narrow_by_label(params[:label_search], page, per), "Active"]
        elsif params[:id_search]
          params[:id_search].strip!
          [entries_with_tags.narrow_by_identifier(params[:id_search], page, per), "Active"]
        elsif params[:tag_search]
          tag_id = params[:tag_search].to_i
          [entries_with_tags.narrow_by_tag(tag_id, page, per), "Active"]
        else
          if params[:mode].present?
            case params[:mode].to_i
            when EntryMode::WHITE
              [entries_with_tags.white.simple_paginate(page, per), "White"]
            when EntryMode::BLACK
              [entries_with_tags.black.simple_paginate(page, per), "Black"]
            when EntryMode::GRAY
              [entries_with_tags.gray.simple_paginate(page, per), "Gray"]
            when EntryMode::ACTIVE
              [entries_with_tags.active.simple_paginate(page, per), "Active"]
            when EntryMode::CUSTOM
              [entries_with_tags.custom.simple_paginate(page, per), "Custom"]
            when EntryMode::AUTO_EXPANDED
              [entries_with_tags.auto_expanded.simple_paginate(page, per), "Auto expanded"]
            else
              [entries_with_tags.active.simple_paginate(page, per), "Active"]
            end
          else
            [entries_with_tags.active.simple_paginate(page, per).load_async, "Active"]
          end
        end
      }
      format.tsv  {
        entries, suffix = if params[:label_search]
          params[:label_search].strip!
          [entries_with_tags.narrow_by_label(params[:label_search]), "label_search_#{params[:label_search]}"]
        elsif params[:id_search]
          params[:id_search].strip!
          [entries_with_tags.narrow_by_identifier(params[:id_search]), "id_search_#{params[:id_search]}"]
        elsif params[:tag_search]
          tag_id = params[:tag_search].to_i
          [entries_with_tags.narrow_by_tag(tag_id, page, per), "tag_search_#{params[:tag_search]}"]
        else
          if params[:mode].present?
            case params[:mode].to_i
            when EntryMode::WHITE
              [entries_with_tags.white, "white"]
            when EntryMode::BLACK
              [entries_with_tags.black, "black"]
            when EntryMode::GRAY
              [entries_with_tags.gray, "gray"]
            when EntryMode::ACTIVE
              [entries_with_tags.active, nil]
            when EntryMode::CUSTOM
              [entries_with_tags.custom, "custom"]
            when EntryMode::AUTO_EXPANDED
              [entries_with_tags.auto_expanded, "auto expanded"]
            else
              [entries_with_tags.active, nil]
            end
          else
            [entries_with_tags.active, nil]
          end
        end

        filename = @dictionary.name
        filename += '_' + suffix if suffix
        if params[:mode].to_i == EntryMode::CUSTOM
          send_data entries.as_tsv_v, filename: "#{filename}.tsv", type: :tsv
        else
          send_data entries.as_tsv, filename: "#{filename}.tsv", type: :tsv
        end
      }
    end

  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      message = "Could not find the dictionary: #{params[:id]}."
      format.html {redirect_to dictionaries_path, notice: message}
      format.any  {render json: {message: message}, status: :bad_request}
    end
  rescue => e
    respond_to do |format|
      format.html { redirect_to dictionaries_url, notice: e.message }
      format.json { head :unprocessable_entity }
      format.tsv  { head :unprocessable_entity }
    end
  end

  def show_patterns
    @dictionary = Dictionary.find_by_name(params[:id])
    raise ArgumentError, "Could not find the dictionary: #{params[:id]}." if @dictionary.nil?

    respond_to do |format|
      page = (params[:page].presence || 1).to_i
      per  = (params[:per].presence || 15).to_i

      format.html {
        @patterns = if params.has_key? 'pattern_search'
          target = params[:pattern_search].strip
          @dictionary.patterns.where("expression ILIKE :target", target: target).simple_paginate(page, per)
        elsif params.has_key? :id_search
          target = params[:id_search].strip
          @dictionary.patterns.where("identifier ILIKE :target", target: target).simple_paginate(page, per)
        else
          @dictionary.patterns.simple_paginate(page, per)
        end
      }
      format.tsv  {
        filename = @dictionary.filename + '_patterns.tsv'
        send_data @dictionary.patterns.as_tsv, filename: filename, type: :tsv
      }
    end

  rescue ArgumentError => e
    respond_to do |format|
      format.html {redirect_to dictionaries_path, notice: e.message}
      format.any  {render json: {message:e.message}, status: :bad_request}
    end
  rescue => e
    respond_to do |format|
      format.html { redirect_to dictionaries_url, notice: e.message }
      format.json { head :unprocessable_entity }
      format.tsv  { head :unprocessable_entity }
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
    @dictionary = current_user.dictionaries.new(dictionary_params)
    tag_list = params[:dictionary][:tag_values].split(/[,|]/).map(&:strip).uniq
    if @dictionary.language.present?
      l = LanguageList::LanguageInfo.find(@dictionary.language)
      if l.nil?
        @dictionary.errors.add(:language, "unrecognizable language")
      else
        @dictionary.language = l.iso_639_3
      end
    end
    @dictionary.name.strip!
    @dictionary.user = current_user

    message  = "An empty dictionary, #{@dictionary.name}, is just created."
    message += "\nAs it is created in the non-public mode, it is visible only in your personal list." unless @dictionary.public

    respond_to do |format|
      if @dictionary.save
        format.html { redirect_to show_user_path(current_user.username), notice: message}
        format.json { render json: {message:message}, status: :created, location: dictionary_url(@dictionary)}
        @dictionary.save_tags(tag_list)
      else
        format.html { render action: "new" }
        format.json { render json: {message:@dictionary.errors}, status: :bad_request}
      end
    end
  end

  def edit
    @dictionary = Dictionary.editable(current_user).find_by!(name: params[:id])
    @submit_text = 'Update'
    @tag_list = @dictionary.tags.map(&:value).join('|')
  end

  def update
    begin
      @dictionary = Dictionary.editable(current_user).find_by(name: params[:id])
      raise ArgumentError, "Cannot find the dictionary" if @dictionary.nil?
      tag_list = params[:dictionary][:tag_values].split(/[,|]/).map(&:strip).uniq

      if dictionary_params[:language].present?
        l = LanguageList::LanguageInfo.find(dictionary_params[:language])
        raise "unrecognizable language: #{dictionary_params[:language]}" if l.nil?
        dictionary_params[:language] = l.iso_639_3
      end

      db_loc_old = @dictionary.sim_string_db_dir
      if @dictionary.update(dictionary_params)
        @dictionary.update_db_location(db_loc_old)
        if @dictionary.update_tags(tag_list)
          redirect_to @dictionary
        else
          flash[:alert] = @dictionary.errors.full_messages.to_sentence
          redirect_back fallback_location: @dictionary
        end
      end

    rescue => e
      redirect_back fallback_location: @dictionary, notice: e.message
    end
  end

  def upload_entries
    @dictionary = Dictionary.editable(current_user).find_by(name: params[:id])
    raise ArgumentError, "Cannot find the dictionary" if @dictionary.nil?
  end

  def downloadable
    dictionary = Dictionary.find_by_name(params[:id])
    raise ArgumentError, "Cannot find the dictionary" if dictionary.nil?

    send_file dictionary.downloadable_zip_path, type: 'application/zip'
  rescue => e
    respond_to do |format|
      format.html {redirect_to dictionary_path(dictionary), notice: e.message}
      format.json {head :no_content}
    end
  end

  def create_downloadable
    dictionary = Dictionary.find_by_name(params[:id])
    raise ArgumentError, "Cannot find the dictionary" if dictionary.nil?

    active_job = CreateDownloadableJob.perform_later(dictionary)
    active_job.create_job_record("Create downloadable")

    respond_to do |format|
      format.html{ redirect_back fallback_location: root_path }
    end
  rescue => e
    respond_to do |format|
      format.html {redirect_to dictionary_path(dictionary), notice: e.message}
      format.json {head :no_content}
    end
  end

  def add_manager
    begin
      @dictionary = Dictionary.editable(current_user).find_by_name(params[:id])
      raise ArgumentError, "Cannot find the dictionary" if @dictionary.nil?

      username = params[:manager_name]
      raise ArgumentError, "Empty username" unless username.present?
      u = User.find_by_username(username)
      raise ArgumentError, "Unknown user" unless u.present?
      raise ArgumentError, "#{u.username} is the owner of the dictionary" if @dictionary.user == u
      raise ArgumentError, "#{u.username} is already a manager of the dictionary" if @dictionary.associated_managers.include?(u)

      @dictionary.associated_managers << u unless @dictionary.user == u || @dictionary.associated_managers.include?(u)

      respond_to do |format|
        format.html{ redirect_back fallback_location: root_path }
      end
    rescue => e
      respond_to do |format|
        format.html{ redirect_back fallback_location: root_path, notice: e.message }
      end
    end
  end

  def remove_manager
    @dictionary = Dictionary.editable(current_user).find_by_name(params[:id])
    raise ArgumentError, "Cannot find the dictionary" if @dictionary.nil?

    username = params[:username]
    u = User.find_by_username(username)
    @dictionary.associated_managers.delete(u) if @dictionary.associated_managers.include?(u)

    respond_to do |format|
      format.html{ redirect_back fallback_location: root_path }
    end
  end

  def empty
    begin
      dictionary = Dictionary.editable(current_user).find_by_name(params[:dictionary_id])
      raise ArgumentError, "Cannot find the dictionary." if dictionary.nil?

      mode = params[:mode]&.to_i

      if mode == EntryMode::PATTERN
        dictionary.empty_patterns
      else
        dictionary.empty_entries(mode)
        dictionary.clear_tags
      end

      respond_to do |format|
        format.html{ redirect_back fallback_location: root_path }
      end
    rescue => e
      respond_to do |format|
        format.html{ redirect_back fallback_location: root_path, notice: e.message }
      end
    end
  end

  def compile
    begin
      dictionary = Dictionary.editable(current_user).find_by_name(params[:id])
      raise ArgumentError, "Cannot find the dictionary" if dictionary.nil?

      # CompileJob.perform_now(dictionary)

      active_job = CompileJob.perform_later(dictionary)
      active_job.create_job_record("Compile entries")

      respond_to do |format|
        format.html{ redirect_back fallback_location: root_path }
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

  private

  def dictionary_params
    @dictionary_params ||= params.require(:dictionary).permit(
      :name,
      :description,
      :language,
      :public,
      :license,
      :license_url,
      :associated_managers,
      :tokens_len_min,
      :tokens_len_max,
      :threshold,
      :associated_annotation_project
    )
  end
end
