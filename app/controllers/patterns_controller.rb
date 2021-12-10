class PatternsController < ApplicationController
	def create
		begin
			dictionary = Dictionary.editable(current_user).find_by_name(params[:dictionary_id])
			raise ArgumentError, "Could not find the dictionary, #{params[:dictionary_id]}." if dictionary.nil?

			expression = params[:expression].strip
			raise ArgumentError, "A pattern should be supplied." unless expression.present?

			identifier = params[:identifier].strip
			raise ArgumentError, "An identifier should be supplied." unless identifier.present?

			pattern = dictionary.patterns.where(expression:expression, identifier:identifier).first
			raise ArgumentError, "The pattern #{pattern} already exists in the dictionary." unless pattern.nil?

			pattern = dictionary.new_pattern(expression, identifier)

			message = if pattern.save
				dictionary.increment!(:patterns_num)
				"The pattern #{pattern} was created."
			else
				"The pattern #{pattern} could not be created."
			end

		rescue => e
			message = e.message
		end

		respond_to do |format|
			format.html { redirect_back fallback_location: root_path, notice: message}
		end
	end

	def upload_tsv
	end

	def destroy
		begin
			dictionary = Dictionary.editable(current_user).find_by_name(params[:dictionary_id])
			raise ArgumentError, "Could not find the dictionary" if dictionary.nil?

			pattern = dictionary.patterns.find(params[:id])
			raise ArgumentError, "Could not find the pattern" if pattern.nil?

			pattern.delete
			dictionary.decrement!(:patterns_num)
		rescue => e
			message = e.message
		end

		respond_to do |format|
			format.html{ redirect_back fallback_location: root_path, notice: message }
		end
	end

	def toggle
		dictionary = Dictionary.editable(current_user).find_by_name(params[:dictionary_id])
		raise ArgumentError, "Could not find the dictionary, #{params[:dictionary_id]}." if dictionary.nil?

		pattern = Pattern.find(params[:id])
		raise ArgumentError, "Could not find the pattern" if pattern.nil?

		pattern.toggle!

		respond_to do |format|
			format.html { redirect_back fallback_location: root_path}
		end
	end
end
