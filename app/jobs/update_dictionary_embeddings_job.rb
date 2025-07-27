require 'concurrent-ruby'

class UpdateDictionaryEmbeddingsJob < ApplicationJob
	queue_as :upload

	# Add retry logic with exponential backoff
	retry_on StandardError, wait: :exponentially_longer, attempts: 3

	def perform(dictionary)
		@dictionary = dictionary
		@total_entries = dictionary.entries.count

		return if @total_entries.zero?

		pool = Concurrent::FixedThreadPool.new(PubDic::Concurrency::ThreadPoolSize)
		count_completed = Concurrent::AtomicFixnum.new(0)
		count_failed = Concurrent::AtomicFixnum.new(0)
		suspended_flag = Concurrent::AtomicBoolean.new(false)

		prepare_progress_record(@total_entries)

		Rails.logger.info "Starting embedding update for dictionary #{dictionary.id} with #{@total_entries} entries"

		# Process entries in batches to avoid memory issues
		dictionary.entries.find_in_batches(batch_size: 100) do |batch|
			break if suspended_flag.true?

			batch.each do |entry|
				break if suspended_flag.true?

				pool.post do
					process_entry(entry, count_completed, count_failed, suspended_flag)
				end

				# Check suspension status periodically
				if suspended?
					suspended_flag.make_true
					break
				end
			end
		end

		# Shutdown pool and wait for completion
		pool.shutdown
		wait_for_completion(pool, count_completed, count_failed, suspended_flag)

		# Final logging
		Rails.logger.info "Embedding update completed: #{count_completed.value} succeeded, #{count_failed.value} failed"

	rescue StandardError => e
		Rails.logger.error "UpdateDictionaryEmbeddingsJob failed: #{e.message}"
		Rails.logger.error e.backtrace.join("\n")
		raise
	ensure
		pool.wait_for_termination
		update_progress_record(count_completed&.value || 0)
		set_ended_at
	end

	private

	def process_entry(entry, count_completed, count_failed, suspended_flag)
		return if suspended_flag.true?

		begin
			entry.update_embedding
			count_completed.increment

			# Log progress every 100 entries
			if count_completed.value % 100 == 0
				Rails.logger.info "Processed #{count_completed.value}/#{@total_entries} entries"
			end

		rescue StandardError => e
			count_failed.increment
			Rails.logger.error "Failed to update embedding for entry #{entry.id}: #{e.message}"

			# Store failed entry for potential retry
			record_failed_entry(entry, e.message)

			# Don't re-raise here to avoid stopping the entire job
			# Individual entry failures shouldn't kill the whole batch
		end
	end

	def wait_for_completion(pool, count_completed, count_failed, suspended_flag)
		until pool.wait_for_termination(1)
			update_progress_record(count_completed.value)
			
			# Check for suspension
			if suspended?
				suspended_flag.make_true
				@job.update(message: "The task is suspended by the user.")
				break
			end
		end
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