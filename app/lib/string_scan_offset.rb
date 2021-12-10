module StringScanOffset
	refine String do
		def scan_offset(regex)
			Enumerator.new do |y|
				self.scan(regex) do
					y << Regexp.last_match
				end
			end
		end
	end
end
