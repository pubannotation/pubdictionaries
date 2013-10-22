module DictionariesHelper
	def is_nil_or_empty?(value)
		if value.nil? or value == ""
			true
		else
			false
		end
	end
end
