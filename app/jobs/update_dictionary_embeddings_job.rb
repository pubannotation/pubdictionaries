require 'concurrent-ruby'

class EmbeddingServerError < StandardError; end
class EmbeddingClientError < StandardError; end

class UpdateDictionaryEmbeddingsJob < ApplicationJob
	queue_as :upload

	# Add retry logic with exponential backoff
	retry_on StandardError, wait: :exponentially_longer, attempts: 3

	BATCH_SIZE = 50 # Optimal batch size for embedding API calls

	def perform(dictionary)
		@dictionary = dictionary
		@total_entries = dictionary.entries.count

		return if @total_entries.zero?

		count_completed = Concurrent::AtomicFixnum.new(0)
		count_failed = Concurrent::AtomicFixnum.new(0)
		suspended_flag = Concurrent::AtomicBoolean.new(false)

		prepare_progress_record(@total_entries)

		Rails.logger.info "Starting embedding update for dictionary #{dictionary.id} with #{@total_entries} entries using PubMedBERT"

		# Process entries in batches to leverage batch embedding API
		dictionary.entries.find_in_batches(batch_size: BATCH_SIZE) do |batch|
			if suspended_flag.true?
				Rails.logger.info "Job suspended - terminating batch processing"
				raise StandardError, "Job was cancelled by user"
			end

			process_batch(batch, count_completed, count_failed, suspended_flag)

				# Check suspension status periodically
			if suspended?
				suspended_flag.make_true
				Rails.logger.info "Job suspended by user request"
				raise StandardError, "Job was cancelled by user"
			end
		end

			# Final logging
		Rails.logger.info "Embedding update completed: #{count_completed.value} succeeded, #{count_failed.value} failed"

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
		update_progress_record(count_completed&.value || 0)
		# Only set ended_at if not already set by error handling
		set_ended_at unless @job&.ended_at.present?
	end

	private

	def process_batch(batch, count_completed, count_failed, suspended_flag)
		if suspended_flag.true?
			Rails.logger.info "Batch processing suspended"
			raise StandardError, "Job was cancelled by user"
		end

		begin
			# Extract labels for batch embedding generation
			labels = batch.map(&:label)

			# Get embeddings for all labels in the batch using PubMedBERT
			embeddings = fetch_embeddings_with_retry(labels)

			# Perform bulk database update using transaction for consistency
			ActiveRecord::Base.transaction do
				bulk_update_embeddings(batch, embeddings)
				count_completed.increment(batch.size)
			end

			# Log progress
			Rails.logger.info "Processed batch: #{count_completed.value}/#{@total_entries} entries completed, #{count_failed.value} failed"

		rescue EmbeddingClientError => e
			# Handle client errors (4xx) - don't retry, fail fast
			Rails.logger.error "Embedding client error (configuration issue) for batch of #{batch.size} entries: #{e.message}"
			handle_client_error(batch, count_completed, count_failed, e)

		rescue EmbeddingServerError => e
			# Handle embedding server specific errors (5xx) - can retry
			Rails.logger.error "Embedding server error for batch of #{batch.size} entries: #{e.message}"
			handle_embedding_server_failure(batch, count_completed, count_failed, e)

		rescue Net::ReadTimeout, Net::OpenTimeout, Timeout::Error => e
			# Handle network timeout errors
			Rails.logger.error "Network timeout error for batch of #{batch.size} entries: #{e.message}"
			handle_network_failure(batch, count_completed, count_failed, e)

		rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH => e
			# Handle connection errors when server is down
			Rails.logger.error "Connection error - embedding server may be down: #{e.message}"
			handle_server_unavailable(batch, count_completed, count_failed, e)

		rescue JSON::ParserError => e
			# Handle malformed JSON responses
			Rails.logger.error "Invalid JSON response from embedding server: #{e.message}"
			handle_malformed_response(batch, count_completed, count_failed, e)

		rescue StandardError => e
			# Handle any other unexpected errors
			Rails.logger.error "Unexpected error in batch processing: #{e.message}"
			Rails.logger.error e.backtrace.join("\n")
			handle_unexpected_error(batch, count_completed, count_failed, e)
		end

		update_progress_record(count_completed.value)
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

	def handle_client_error(batch, count_completed, count_failed, error)
		# Client errors indicate configuration issues - fail fast, don't retry
		Rails.logger.fatal "CRITICAL: Embedding client error detected - this likely indicates a configuration issue (wrong model, API key, etc.)"
		Rails.logger.fatal "Error details: #{error.message}"
		Rails.logger.fatal "JOB TERMINATING - Fix configuration before retrying"

		# Mark all remaining entries as failed and terminate the job
		count_failed.increment(batch.size)
		batch.each { |entry| record_failed_entry(entry, "Configuration error: #{error.message}") }

		# Raise to terminate the entire job - don't continue processing
		raise error
	end

	def handle_embedding_server_failure(batch, count_completed, count_failed, error)
		# For server errors, mark all entries as failed and terminate job
		Rails.logger.fatal "CRITICAL: Embedding server error detected - terminating job immediately"
		Rails.logger.fatal "Error details: #{error.message}"
		Rails.logger.fatal "JOB TERMINATING - Fix server issues before retrying"

		count_failed.increment(batch.size)
		batch.each { |entry| record_failed_entry(entry, "Embedding server error: #{error.message}") }

		# Raise to terminate the entire job
		raise error
	end

	def handle_network_failure(batch, count_completed, count_failed, error)
		# For network timeouts, terminate job immediately
		Rails.logger.fatal "CRITICAL: Network timeout error detected - terminating job immediately"
		Rails.logger.fatal "Error details: #{error.message}"
		Rails.logger.fatal "JOB TERMINATING - Fix network/server connectivity before retrying"

		count_failed.increment(batch.size)
		batch.each { |entry| record_failed_entry(entry, "Network timeout: #{error.message}") }

		# Raise to terminate the entire job
		raise error
	end

	def handle_server_unavailable(batch, count_completed, count_failed, error)
		# Server is completely down - terminate job immediately
		Rails.logger.fatal "CRITICAL: Embedding server unavailable - terminating job immediately"
		Rails.logger.fatal "Error details: #{error.message}"
		Rails.logger.fatal "JOB TERMINATING - Ensure embedding server is running before retrying"

		count_failed.increment(batch.size)
		batch.each { |entry| record_failed_entry(entry, "Server unavailable: #{error.message}") }

		# Raise to terminate the entire job
		raise error
	end

	def handle_malformed_response(batch, count_completed, count_failed, error)
		# Malformed response - terminate job immediately
		Rails.logger.fatal "CRITICAL: Malformed response from embedding server - terminating job immediately"
		Rails.logger.fatal "Error details: #{error.message}"
		Rails.logger.fatal "JOB TERMINATING - Check server response format"

		count_failed.increment(batch.size)
		batch.each { |entry| record_failed_entry(entry, "Malformed response: #{error.message}") }

		# Raise to terminate the entire job
		raise error
	end

	def handle_unexpected_error(batch, count_completed, count_failed, error)
		# For unexpected errors, terminate job immediately
		Rails.logger.fatal "CRITICAL: Unexpected error in batch processing - terminating job immediately"
		Rails.logger.fatal "Error details: #{error.message}"
		Rails.logger.fatal "JOB TERMINATING - Review error details before retrying"

		count_failed.increment(batch.size)
		batch.each { |entry| record_failed_entry(entry, "Unexpected error: #{error.message}") }

		# Raise to terminate the entire job
		raise error
	end


	def record_failed_entry(entry, error_message)
		# Store failed entries for potential retry or manual review
		Rails.cache.write(
			"failed_embedding_#{@dictionary.id}_#{entry.id}",
			{ entry_id: entry.id, error: error_message, timestamp: Time.current },
			expires_in: 1.week
		)
	end

	def prepare_progress_record(total)
		@start_time = Time.current
		super(total)
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