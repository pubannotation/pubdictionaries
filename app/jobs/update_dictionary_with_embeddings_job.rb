require 'concurrent-ruby'

class UpdateDictionaryWithEmbeddingsJob < ApplicationJob
	queue_as :upload

	def perform(dictionary)
		pool = Concurrent::FixedThreadPool.new(PubDic::Concurrency::ThreadPoolSize)
		count_completed = Concurrent::AtomicFixnum.new(0) # Thread-safe counter for completed tasks
		suspended_flag = Concurrent::AtomicBoolean.new(false)

		prepare_progress_record(dictionary.entries.count)

		dictionary.entries.each do |entry|
			pool.post do
				begin
					unless suspended_flag.true?
						entry.update_embedding
						count_completed.increment
					end
				rescue StandardError => e
					raise "[#{entry}] #{e.message}"
				end
			end
			if suspended?
				suspended_flag.make_true
				break
			end
		end

		pool.shutdown
		until pool.wait_for_termination(1)
			update_progress_record(count_completed.value)
			if suspended?
				suspended_flag.make_true
	      @job.update(message: "The task is suspended by the user.")
				break
			end
		end
		pool.wait_for_termination
	ensure
		update_progress_record(count_completed.value)
		set_ended_at
	end

	before_perform do |active_job|
		set_job(active_job)
		set_begun_at
	end

	after_perform do
		set_ended_at
	end
end
