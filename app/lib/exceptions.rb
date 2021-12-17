module Exceptions
  class JobSuspendError < StandardError
    def initialize(msg = "Job was stopped.")
      super(msg)
    end
  end
end
