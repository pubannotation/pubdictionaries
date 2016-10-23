class CompileJob < Struct.new(:dictionary)
	include StateManagement

	def perform
		begin
			dictionary.compile
		rescue => e
			@job.message = e.message
		end
	end
end
