class DestroyDictionaryJob < Struct.new(:dictionary)
	include StateManagement

	def perform
    begin
      dictionary.destroy
    rescue => e
			@job.message = e.message
    end
	end
end
