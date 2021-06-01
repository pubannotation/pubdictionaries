class CompileJob < ApplicationJob
  queue_as :general

  def perform(dictionary)
    dictionary.compile!
  end

  before_perform do |active_job|
    set_job(active_job)
    set_begun_at
  end

  after_perform do
    set_ended_at
  end
end
