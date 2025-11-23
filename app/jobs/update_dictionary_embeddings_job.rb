class EmbeddingServerError < StandardError; end
class EmbeddingClientError < StandardError; end

class UpdateDictionaryEmbeddingsJob < ApplicationJob
	queue_as :upload

	# Note: No job-level retry is configured. Transient errors (network timeouts, connection
	# failures) are handled by fetch_embeddings_with_retry with proper exponential backoff.
	# Non-transient errors (client/server errors) should not be automatically retried as they
	# require manual intervention to fix configuration or server issues.

	BATCH_SIZE = 50 # Optimal batch size for embedding API calls

	def perform(dictionary, embedding_model: EmbeddingServer::DEFAULT_MODEL,
	            clean_embeddings: true, clean_two_stage: false,
	            global_distance_threshold: 0.75, local_z_threshold: 2.0,
	            min_cluster_size: 3, origin_terms: ['DNA', 'protein'])
		@dictionary = dictionary
		@total_entries = dictionary.entries.count
		@count_completed = 0
		@count_failed = 0
		@failed_entries = []
		@batch_count = 0
		@embedding_model = embedding_model
		@clean_embeddings = clean_embeddings
		@clean_two_stage = clean_two_stage
		@global_distance_threshold = global_distance_threshold
		@local_z_threshold = local_z_threshold
		@min_cluster_size = min_cluster_size
		@origin_terms = origin_terms

		return if @total_entries.zero?

		prepare_progress_record(@total_entries)

		Rails.logger.info "Starting embedding update for dictionary #{dictionary.id} with #{@total_entries} entries using #{@embedding_model}"

		# Reset all entries to searchable so they get re-evaluated
		# Outlier detection will mark problematic entries as non-searchable later
		reset_count = dictionary.entries.where(searchable: false).update_all(searchable: true)
		Rails.logger.info "Reset #{reset_count} entries to searchable" if reset_count > 0

		# Ensure semantic table exists before processing
		@dictionary.create_semantic_table! unless @dictionary.has_semantic_table?

		# Process all entries in batches
		dictionary.entries.find_in_batches(batch_size: BATCH_SIZE) do |batch|
			check_suspension
			process_batch(batch)
		end

		# Final logging
		Rails.logger.info "Embedding update completed: #{@count_completed} succeeded, #{@count_failed} failed"

		# Clean embeddings after successful update
		@cleanup_stats = nil
		if @clean_embeddings && @count_completed > 0
			Rails.logger.info "Starting post-update embedding cleanup..."
			@cleanup_stats = perform_embedding_cleanup
		end

		# Generate and log summary report
		generate_summary_report

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

	def perform_embedding_cleanup
		begin
			# Note: searchable flags are already reset at the start of the job
			# Initialize analyzer
			analyzer = DictionaryEmbeddingAnalyzer.new(@dictionary.name)

			# Perform cleaning
			if @clean_two_stage
				Rails.logger.info "Performing two-stage cleaning (global + local outliers)..."
				stats = analyzer.clean_dictionary_two_stage(
					origin_terms: @origin_terms,
					global_distance_threshold: @global_distance_threshold,
					local_z_threshold: @local_z_threshold,
					min_cluster_size: @min_cluster_size,
					dry_run: false
				)

				Rails.logger.info "Two-stage cleaning completed:"
				Rails.logger.info "  Stage 1 (global): #{stats[:stage1_global][:outliers_found]} outliers"
				Rails.logger.info "  Stage 2 (local): #{stats[:stage2_local][:outliers_found]} outliers"
				Rails.logger.info "  Total marked non-searchable: #{stats[:marked_unsearchable]}"
			else
				Rails.logger.info "Performing single-stage cleaning (global outliers only)..."
				stats = analyzer.clean_by_origin_proximity(
					origin_terms: @origin_terms,
					distance_threshold: @global_distance_threshold,
					dry_run: false
				)

				Rails.logger.info "Single-stage cleaning completed:"
				Rails.logger.info "  Outliers found: #{stats[:outliers_found]}"
				Rails.logger.info "  Marked non-searchable: #{stats[:marked_unsearchable]}"
			end

			# Return stats for summary report
			stats

		rescue => e
			Rails.logger.error "Embedding cleanup failed: #{e.message}"
			Rails.logger.error e.backtrace.join("\n")
			# Return error info
			{ error: e.message }
		end
	end

	def generate_summary_report
		# Calculate final statistics from semantic table
		if @dictionary.has_semantic_table?
			table = @dictionary.semantic_table_name
			total_with_embeddings = ActiveRecord::Base.connection.exec_query(
				"SELECT COUNT(*) as cnt FROM #{table}"
			).first['cnt']
			total_searchable = ActiveRecord::Base.connection.exec_query(
				"SELECT COUNT(*) as cnt FROM #{table} WHERE searchable = true"
			).first['cnt']
			total_non_searchable = total_with_embeddings - total_searchable
		else
			total_with_embeddings = 0
			total_searchable = 0
			total_non_searchable = 0
		end

		# Build summary
		summary = {
			dictionary: @dictionary.name,
			total_entries: @total_entries,
			updated_at: Time.current.iso8601,
			embedding_update: {
				completed: @count_completed,
				failed: @count_failed,
				success_rate: @total_entries > 0 ? (@count_completed.to_f / @total_entries * 100).round(2) : 0
			},
			embedding_status: {
				total_with_embeddings: total_with_embeddings,
				searchable: total_searchable,
				non_searchable: total_non_searchable,
				searchable_percentage: total_with_embeddings > 0 ? (total_searchable.to_f / total_with_embeddings * 100).round(2) : 0
			}
		}

		# Add cleaning summary if performed
		if @clean_embeddings
			if @cleanup_stats && !@cleanup_stats[:error]
				if @clean_two_stage
					summary[:cleaning] = {
						enabled: true,
						mode: 'two-stage',
						stage1_global: {
							outliers_found: @cleanup_stats[:stage1_global][:outliers_found],
							distribution: @cleanup_stats[:stage1_global][:distribution]
						},
						stage2_local: {
							outliers_found: @cleanup_stats[:stage2_local][:outliers_found],
							z_threshold: @cleanup_stats[:stage2_local][:z_threshold],
							min_cluster_size: @cleanup_stats[:stage2_local][:min_cluster_size]
						},
						total_outliers: @cleanup_stats[:total_outliers],
						marked_non_searchable: @cleanup_stats[:marked_unsearchable],
						distance_stats: @cleanup_stats[:distance_stats],
						validation: @cleanup_stats[:validation],
						parameters: {
							global_threshold: @global_distance_threshold,
							local_z_threshold: @local_z_threshold,
							min_cluster_size: @min_cluster_size,
							origin_terms: @origin_terms
						}
					}
				else
					summary[:cleaning] = {
						enabled: true,
						mode: 'single-stage',
						outliers_found: @cleanup_stats[:outliers_found],
						distribution: @cleanup_stats[:distribution],
						marked_non_searchable: @cleanup_stats[:marked_unsearchable],
						distance_stats: @cleanup_stats[:distance_stats],
						validation: @cleanup_stats[:validation],
						parameters: {
							global_threshold: @global_distance_threshold,
							origin_terms: @origin_terms
						}
					}
				end
			elsif @cleanup_stats && @cleanup_stats[:error]
				summary[:cleaning] = {
					enabled: true,
					error: @cleanup_stats[:error]
				}
			end
		else
			summary[:cleaning] = { enabled: false }
		end

		# Store summary in job metadata (for backward compatibility)
		@job&.update(metadata: (@job.metadata || {}).merge(summary: summary))

		# Store summary persistently in dictionary (survives job cleanup)
		@dictionary.update(
			embedding_model: @embedding_model,
			embedding_report: summary
		)

		# Log formatted summary
		log_summary(summary)

		summary
	end

	def log_summary(summary)
		Rails.logger.info ""
		Rails.logger.info "=" * 80
		Rails.logger.info "EMBEDDING UPDATE JOB SUMMARY"
		Rails.logger.info "=" * 80
		Rails.logger.info ""
		Rails.logger.info "Dictionary: #{summary[:dictionary]}"
		Rails.logger.info "Total entries: #{summary[:total_entries]}"
		Rails.logger.info ""
		Rails.logger.info "Embedding Update:"
		Rails.logger.info "  Completed: #{summary[:embedding_update][:completed]}"
		Rails.logger.info "  Failed: #{summary[:embedding_update][:failed]}"
		Rails.logger.info "  Success rate: #{summary[:embedding_update][:success_rate]}%"
		Rails.logger.info ""
		Rails.logger.info "Embedding Status:"
		Rails.logger.info "  Total with embeddings: #{summary[:embedding_status][:total_with_embeddings]}"
		Rails.logger.info "  Searchable: #{summary[:embedding_status][:searchable]}"
		Rails.logger.info "  Non-searchable: #{summary[:embedding_status][:non_searchable]}"
		Rails.logger.info "  Searchable percentage: #{summary[:embedding_status][:searchable_percentage]}%"
		Rails.logger.info ""

		if summary[:cleaning][:enabled]
			if summary[:cleaning][:error]
				Rails.logger.info "Cleaning: FAILED"
				Rails.logger.info "  Error: #{summary[:cleaning][:error]}"
			else
				Rails.logger.info "Cleaning: #{summary[:cleaning][:mode].upcase}"

				if summary[:cleaning][:mode] == 'two-stage'
					Rails.logger.info "  Stage 1 (Global):"
					Rails.logger.info "    Outliers found: #{summary[:cleaning][:stage1_global][:outliers_found]}"
					summary[:cleaning][:stage1_global][:distribution]&.each do |origin, count|
						Rails.logger.info "      #{origin}: #{count}"
					end
					Rails.logger.info "  Stage 2 (Local):"
					Rails.logger.info "    Outliers found: #{summary[:cleaning][:stage2_local][:outliers_found]}"
					Rails.logger.info "    Z-threshold: #{summary[:cleaning][:stage2_local][:z_threshold]}"
					Rails.logger.info "    Min cluster size: #{summary[:cleaning][:stage2_local][:min_cluster_size]}"
					Rails.logger.info "  Total outliers: #{summary[:cleaning][:total_outliers]}"
					Rails.logger.info "  Marked non-searchable: #{summary[:cleaning][:marked_non_searchable]}"
				else
					Rails.logger.info "  Outliers found: #{summary[:cleaning][:outliers_found]}"
					summary[:cleaning][:distribution]&.each do |origin, count|
						Rails.logger.info "    #{origin}: #{count}"
					end
					Rails.logger.info "  Marked non-searchable: #{summary[:cleaning][:marked_non_searchable]}"
				end

				Rails.logger.info "  Parameters:"
				Rails.logger.info "    Global threshold: #{summary[:cleaning][:parameters][:global_threshold]}"
				Rails.logger.info "    Origin terms: #{summary[:cleaning][:parameters][:origin_terms].join(', ')}"
				if summary[:cleaning][:mode] == 'two-stage'
					Rails.logger.info "    Local z-threshold: #{summary[:cleaning][:parameters][:local_z_threshold]}"
					Rails.logger.info "    Min cluster size: #{summary[:cleaning][:parameters][:min_cluster_size]}"
				end
			end
		else
			Rails.logger.info "Cleaning: DISABLED"
		end

		Rails.logger.info ""
		Rails.logger.info "=" * 80
		Rails.logger.info ""
	end

	def process_batch(batch)
		begin
			# Extract labels for batch embedding generation
			labels = batch.map(&:label)

			# Get embeddings for all labels in the batch
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
			EmbeddingServer.fetch_embeddings(labels, model: @embedding_model)
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

		# Prepare bulk upsert to semantic table
		entries_data = batch.zip(embeddings).map do |entry, embedding|
			{
				id: entry.id,
				label: entry.label,
				identifier: entry.identifier,
				embedding: embedding
			}
		end

		@dictionary.bulk_upsert_semantic_embeddings(entries_data)

		Rails.logger.debug "Bulk upserted #{batch.size} entries to semantic table"
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