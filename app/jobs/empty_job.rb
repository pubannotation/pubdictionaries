class EmptyJob < ApplicationJob
	queue_as :general

	def perform(dictionary, mode)
		dictionary.empty_entries(mode)
		dictionary.clear_tags if mode == EntryMode::GRAY
	end

	before_perform do |active_job|
		set_job(active_job)
		set_begun_at
	end

	after_perform do
		set_ended_at
	end
end
