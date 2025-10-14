class EmbeddingServerError < StandardError; end
class EmbeddingClientError < StandardError; end

class UpdateDictionaryEmbeddingsJob < ApplicationJob
	queue_as :upload

	# Note: No job-level retry is configured. Transient errors (network timeouts, connection
	# failures) are handled by fetch_embeddings_with_retry with proper exponential backoff.
	# Non-transient errors (client/server errors) should not be automatically retried as they
	# require manual intervention to fix configuration or server issues.

	BATCH_SIZE = 50 # Optimal batch size for embedding API calls

	def perform(dictionary)
		@dictionary = dictionary
		@total_entries = dictionary.entries.count
		@count_completed = 0
		@count_failed = 0
		@failed_entries = []
		@batch_count = 0

		return if @total_entries.zero?

		prepare_progress_record(@total_entries)

		Rails.logger.info "Starting embedding update for dictionary #{dictionary.id} with #{@total_entries} entries using PubMedBERT"

		# Process entries in batches to leverage batch embedding API
		dictionary.entries.find_in_batches(batch_size: BATCH_SIZE) do |batch|
			check_suspension
			process_batch(batch)
		end

		# Final logging
		Rails.logger.info "Embedding update completed: #{@count_completed} succeeded, #{@count_failed} failed"

	rescue StandardError => e
		# Explicitly handle errors to ensure job record is updated
		Rails.logger.error "UpdateDictionaryEmbeddingsJob failed: #{e.message}"
		Rails.logger.error e.backtrace.join("\n")

		# Ensure job record shows failure
		if @job
			@job.update(message: e.message, ended_at: Time.now)
		else
			# Fallback: find job by active_job_id and update it
			job = Job.find_by(active_job_id: job_id)
			job&.update(message: e.message, ended_at: Time.now)
		end

		raise e
	ensure
		update_progress_record(@count_completed)

		# Log performance metrics
		if @start_time && @total_entries && @total_entries > 0
			duration = Time.current - @start_time
			rate = (@count_completed / duration).round(2)
			Rails.logger.info "Performance: #{duration.round(2)}s total, #{rate} entries/sec"
		end

		# Store failed entries in job metadata for display in UI
		if @failed_entries.any?
			Rails.logger.warn "[UpdateDictionaryEmbeddingsJob] #{@failed_entries.size} entries failed"
			@failed_entries.first(100).each do |entry|
				Rails.logger.warn "  - Entry #{entry[:entry_id]} (#{entry[:label]}): #{entry[:error]}"
			end

			# Limit to first 100 to avoid huge metadata
			@job&.update(metadata: { failed_entries: @failed_entries.first(100) })
		end

		# Only set ended_at if not already set by error handling
		set_ended_at unless @job&.ended_at.present?
	end

	private

	def process_batch(batch)
		begin
			# Extract labels for batch embedding generation
			labels = batch.map(&:label)

			# Get embeddings for all labels in the batch using PubMedBERT
			embeddings = fetch_embeddings_with_retry(labels)

			# Perform bulk database update using transaction for consistency
			ActiveRecord::Base.transaction do
				bulk_update_embeddings(batch, embeddings)
				@count_completed += batch.size
			end

			@batch_count += 1

			# Log progress
			Rails.logger.info "Processed batch: #{@count_completed}/#{@total_entries} entries completed, #{@count_failed} failed"

		rescue EmbeddingClientError => e
			# Handle client errors (4xx) - don't retry, fail fast
			Rails.logger.error "Embedding client error (configuration issue) for batch of #{batch.size} entries: #{e.message}"
			handle_batch_error(batch, e,
				"Embedding client error detected - this likely indicates a configuration issue (wrong model, API key, etc.)",
				"Configuration error")

		rescue EmbeddingServerError => e
			# Handle embedding server specific errors (5xx) - can retry
			Rails.logger.error "Embedding server error for batch of #{batch.size} entries: #{e.message}"
			handle_batch_error(batch, e,
				"Embedding server error detected - terminating job immediately",
				"Embedding server error")

		rescue Net::ReadTimeout, Net::OpenTimeout, Timeout::Error => e
			# Handle network timeout errors
			Rails.logger.error "Network timeout error for batch of #{batch.size} entries: #{e.message}"
			handle_batch_error(batch, e,
				"Network timeout error detected - terminating job immediately",
				"Network timeout")

		rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH => e
			# Handle connection errors when server is down
			Rails.logger.error "Connection error - embedding server may be down: #{e.message}"
			handle_batch_error(batch, e,
				"Embedding server unavailable - terminating job immediately",
				"Server unavailable")

		rescue JSON::ParserError => e
			# Handle malformed JSON responses
			Rails.logger.error "Invalid JSON response from embedding server: #{e.message}"
			handle_batch_error(batch, e,
				"Malformed response from embedding server - terminating job immediately",
				"Malformed response")

		rescue StandardError => e
			# Handle any other unexpected errors
			Rails.logger.error "Unexpected error in batch processing: #{e.message}"
			Rails.logger.error e.backtrace.join("\n")
			handle_batch_error(batch, e,
				"Unexpected error in batch processing - terminating job immediately",
				"Unexpected error")
		end

		# Update progress every 5 batches to reduce database writes
		update_progress_record(@count_completed) if @batch_count % 5 == 0
	end


	def fetch_embeddings_with_retry(labels, max_retries: 3)
		retries = 0
		begin
			EmbeddingServer.fetch_embeddings(labels)
		rescue Net::ReadTimeout, Net::OpenTimeout, Timeout::Error, Errno::ECONNREFUSED => e
			retries += 1
			if retries <= max_retries
				wait_time = retries * 2 # Exponential backoff: 2, 4, 6 seconds
				Rails.logger.warn "Embedding server request failed (attempt #{retries}/#{max_retries}), retrying in #{wait_time} seconds: #{e.message}"
				sleep(wait_time)
				retry
			else
				Rails.logger.error "Embedding server failed after #{max_retries} retries: #{e.message}"
				raise EmbeddingServerError.new("Embedding server unavailable after #{max_retries} retries: #{e.message}")
			end
		rescue EmbeddingClientError => e
			# Client errors should not be retried
			raise e
		rescue => e
			# For other errors, don't retry but wrap in custom exception
			raise EmbeddingServerError.new("Embedding server error: #{e.message}")
		end
	end

	def bulk_update_embeddings(batch, embeddings)
		return if batch.empty? || embeddings.empty?

		# Prepare the bulk update using PostgreSQL's UPDATE ... FROM with VALUES
		connection = ActiveRecord::Base.connection

		# Build values list for the query
		values_list = batch.zip(embeddings).map do |entry, embedding|
			# Safely format the embedding vector and escape entry ID
			embedding_str = connection.quote("[#{embedding.join(',')}]")
			"(#{entry.id}, #{embedding_str}::vector)"
		end.join(', ')

		# Execute bulk update using VALUES clause for better performance
		sql = <<~SQL
			UPDATE entries
			SET embedding = updates.embedding_data
			FROM (VALUES #{values_list}) AS updates(id, embedding_data)
			WHERE entries.id = updates.id
		SQL

		connection.execute(sql)

		Rails.logger.debug "Bulk updated #{batch.size} entries with embeddings"
	end

	def handle_batch_error(batch, error, error_description, error_prefix)
		# Consolidated error handler for all batch processing errors
		Rails.logger.fatal "CRITICAL: #{error_description}"
		Rails.logger.fatal "Error details: #{error.message}"
		Rails.logger.fatal "JOB TERMINATING - Fix issues before retrying"

		# Mark all entries in batch as failed
		@count_failed += batch.size
		batch.each { |entry| record_failed_entry(entry, "#{error_prefix}: #{error.message}") }

		# Raise to terminate the entire job
		raise error
	end


	def record_failed_entry(entry, error_message)
		# Store failed entries in memory for later persistence to Job metadata
		@failed_entries << {
			entry_id: entry.id,
			label: entry.label,
			identifier: entry.identifier,
			error: error_message,
			timestamp: Time.current.iso8601
		}
	end

	def prepare_progress_record(total)
		@start_time = Time.current
		super(total)
	end

	def check_suspension
		raise Exceptions::JobSuspendError if suspended?
	end

	# Callbacks
	before_perform do |active_job|
		set_job(active_job)
		set_begun_at
	end

	after_perform do
		set_ended_at
	end
end