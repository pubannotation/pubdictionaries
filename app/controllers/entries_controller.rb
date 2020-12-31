class EntriesController < ApplicationController
	# Requires authentication for all actions
	before_action :authenticate_user!, except: [:index]

	# GET /dictionaries/dic1/entries?page=1&per_page=20
	def index
		dictionary = Dictionary.find_by_name(params[:dictionary_id])
		raise ArgumentError, "Unknown dictionary: #{params[:dictionary_id]}." if dictionary.nil?

		entries = dictionary.entries.order("mode DESC").order(:label).page(params[:page]).per(params[:per_page])

		respond_to do |format|
			format.json { render json: entries }
		end
	rescue ArgumentError => e
		respond_to do |format|
			format.html {flash.now[:notice] = e.message}
			format.any {render json: {message:e.message}, status: :bad_request}
		end
	rescue => e
		respond_to do |format|
			format.html { redirect_to dictionaries_url, notice: e.message }
			format.json { head :unprocessable_entity }
			format.tsv  { head :unprocessable_entity }
		end
	end

	def create
		begin
			dictionary = Dictionary.editable(current_user).find_by_name(params[:dictionary_id])

			raise ArgumentError, "Cannot find the dictionary, #{params[:dictionary_id]}." if dictionary.nil?

			dictionary.create_addition(params[:label].strip, params[:identifier].strip)

		rescue => e
			message = e.message
		end

		respond_to do |format|
			format.html { redirect_back fallback_location: root_path, notice: message }
		end
	end

	def upload_tsv
		begin
			dictionary = Dictionary.editable(current_user).find_by_name(params[:dictionary_id])

			raise ArgumentError, "Cannot find the dictionary, #{params[:dictionary_id]}." if dictionary.nil?
			raise RuntimeError, "The last task is not yet dismissed. Please dismiss it and try again." if dictionary.jobs.count > 0

			source_filepath = params[:file].tempfile.path
			target_filepath = File.join('tmp', "upload-#{dictionary.name}-#{Time.now.to_s[0..18].gsub(/[ :]/, '-')}")
			FileUtils.cp source_filepath, target_filepath

			# delayed_job = LoadEntriesFromFileJob.new(target_filepath, dictionary)
			# delayed_job.perform

			delayed_job = Delayed::Job.enqueue LoadEntriesFromFileJob.new(target_filepath, dictionary), queue: :upload
			Job.create({name:"Upload dictionary entries", dictionary_id:dictionary.id, delayed_job_id:delayed_job.id})
			message = ''

		rescue => e
			message = e.message
		end

		respond_to do |format|
			format.html { redirect_back fallback_location: root_path, notice: message }
		end
	end

	def destroy
		begin
			dictionary = Dictionary.editable(current_user).find_by_name(params[:dictionary_id])
			raise ArgumentError, "Cannot find the dictionary" if dictionary.nil?

			entry = Entry.find(params[:id])
			raise ArgumentError, "Cannot find the entry" if entry.nil?

			dictionary.create_deletion(entry)
		rescue => e
			message = e.message
		end

		respond_to do |format|
			format.html{ redirect_back fallback_location: root_path, notice: message }
		end
	end

	def destroy_entries
		begin
			dictionary = Dictionary.editable(current_user).find_by_name(params[:dictionary_id])
			raise ArgumentError, "Cannot find the dictionary" if dictionary.nil?

			raise ArgumentError, "No entry to be deleted is selected" unless params[:entry_id].present?

			entries = params[:entry_id].collect{|id| Entry.find(id)}
			entries.each{|entry| dictionary.create_deletion(entry)}
		rescue => e
			message = e.message
		end

		respond_to do |format|
			format.html{ redirect_back fallback_location: root_path, notice: message }
		end
	end

	def undo
		begin
			dictionary = Dictionary.editable(current_user).find_by_name(params[:dictionary_id])
			raise ArgumentError, "Cannot find the dictionary" if dictionary.nil?

			entry = Entry.find(params[:id])
			raise ArgumentError, "Cannot find the entry" if entry.nil?

			dictionary.undo_entry(entry)
		rescue => e
			message = e.message
		end

		respond_to do |format|
			format.html{ redirect_back fallback_location: root_path, notice: message }
		end
	end
end
