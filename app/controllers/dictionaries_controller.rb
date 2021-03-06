require 'set'
require 'pathname'
require 'fileutils'
require 'pp'

class DictionariesController < ApplicationController
	# Require authentication for all actions except :index, :show, and some others.
	before_action :authenticate_user!, except: [
		:index, :show,
		:find_ids, :text_annotation,
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

		respond_to do |format|
			format.html # index.html.erb
			format.json { render json: dics }
		end
	end

	def show
		@dictionary = Dictionary.find_by_name(params[:id])
		raise ArgumentError, "Could not find the dictionary: #{params[:id]}." if @dictionary.nil?

		respond_to do |format|
			page = (params[:page].presence || 1).to_i
			per  = (params[:per].presence || 15).to_i

			format.html {
				@entries, @type_entries = if params[:label_search]
					params[:label_search].strip!
					[@dictionary.narrow_entries_by_label(params[:label_search], page, per), "Active"]
				elsif params[:id_search]
					params[:id_search].strip!
					[@dictionary.narrow_entries_by_identifier(params[:id_search], page, per), "Active"]
				else
					if params[:mode].present?
						case params[:mode].to_i
						when Entry::MODE_WHITE
							[@dictionary.entries.white.simple_paginate(page, per), "White"]
						when Entry::MODE_BLACK
							[@dictionary.entries.black.simple_paginate(page, per), "Black"]
						when Entry::MODE_GRAY
							[@dictionary.entries.gray.simple_paginate(page, per), "Gray"]
						when Entry::MODE_ACTIVE
							[@dictionary.entries.active.simple_paginate(page, per), "Active"]
						when Entry::MODE_CUSTOM
							[@dictionary.entries.custom.simple_paginate(page, per), "Custom"]
						else
							[@dictionary.entries.active.simple_paginate(page, per), "Active"]
						end
					else
						[@dictionary.entries.active.simple_paginate(page, per), "Active"]
					end
				end
			}
			format.tsv  {
				entries, suffix = if params[:label_search]
					params[:label_search].strip!
					[@dictionary.narrow_entries_by_label(params[:label_search]), "label_search_#{params[:label_search]}"]
				elsif params[:id_search]
					params[:id_search].strip!
					[@dictionary.narrow_entries_by_identifier(params[:id_search]), "id_search_#{params[:id_search]}"]
				else
					if params[:mode].present?
						case params[:mode].to_i
						when Entry::MODE_WHITE
							[@dictionary.entries.added, "white"]
						when Entry::MODE_BLACK
							[@dictionary.entries.deleted, "black"]
						when Entry::MODE_GRAY
							[@dictionary.entries.gray, "gray"]
						when Entry::MODE_ACTIVE
							[@dictionary.entries.active, nil]
						when Entry::MODE_CUSTOM
							[@dictionary.entries.custom, "custom"]
						else
							[@dictionary.entries.active, nil]
						end
					else
						[@dictionary.entries.active, nil]
					end
				end

				filename = @dictionary.name
				filename += '_' + suffix if suffix
				if params[:mode].to_i == Entry::MODE_CUSTOM
					send_data entries.as_tsv_v,  filename: "#{filename}.tsv", type: :tsv
				else
					send_data entries.as_tsv,  filename: "#{filename}.tsv", type: :tsv
				end
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
			else
				format.html { render action: "new" }
				format.json { render json: {message:@dictionary.errors}, status: :bad_request}
			end
		end
	end

	def edit
		@dictionary = Dictionary.editable(current_user).find_by_name(params[:id])
		raise ArgumentError, "Cannot find the dictionary" if @dictionary.nil?
		@submit_text = 'Update'
	end
	
	def update
		begin
			@dictionary = Dictionary.editable(current_user).find_by_name(params[:id])
			raise ArgumentError, "Cannot find the dictionary" if @dictionary.nil?

			if dictionary_params[:language].present?
				l = LanguageList::LanguageInfo.find(dictionary_params[:language])
				raise "unrecognizable language: #{dictionary_params[:language]}" if l.nil?
				dictionary_params[:language] = l.iso_639_3
			end

			db_loc_old = @dictionary.sim_string_db_dir
			if @dictionary.update(dictionary_params)
				db_loc_new = @dictionary.sim_string_db_dir
				FileUtils.mv db_loc_old, db_loc_new unless db_loc_new == db_loc_old
			end

			redirect_to @dictionary
		rescue => e
			redirect_back fallback_location: @dictionary, notice: e.message
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

			dictionary.empty_entries

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
			:threshold
		)
	end
end
