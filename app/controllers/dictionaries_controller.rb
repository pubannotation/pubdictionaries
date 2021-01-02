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
		begin
			@dictionary = Dictionary.find_by_name(params[:id])
			raise ArgumentError, "Could not find the dictionary: #{params[:id]}." if @dictionary.nil?

			@entries = if params[:label_search]
				params[:label_search].strip!
				@dictionary.narrow_entries_by_label(params[:label_search], params[:page])
			elsif params[:id_search]
				params[:id_search].strip!
				@dictionary.narrow_entries_by_identifier(params[:id_search], params[:page])
			else
				if params[:mode].present?
					if params[:mode].to_i == Entry::MODE_ADDITION
						@dictionary.entries.added.page(params[:page])
					elsif params[:mode].to_i == Entry::MODE_DELETION
						@dictionary.entries.deleted.page(params[:page])
					else
						@dictionary.entries.active.page(params[:page])
					end
				else
					@dictionary.entries.active.page(params[:page])
				end
			end

			@addition_num = @dictionary.num_addition
			@deletion_num = @dictionary.num_deletion

			respond_to do |format|
				format.html
				format.json { render json: @dictionary.as_json }
				format.tsv  { send_data @dictionary.entries.as_tsv,  filename: "#{@dictionary.name}.tsv",  type: :tsv  }
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
			if @dictionary.update_attributes(dictionary_params)
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

			delayed_job = Delayed::Job.enqueue CompileJob.new(dictionary), queue: :general
			Job.create({name:"Compile entries", dictionary_id:dictionary.id, delayed_job_id:delayed_job.id})

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
