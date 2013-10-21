module DictionariesHelper
	def sortable(dictionary, column, anchor )
		if dictionary == sort_dictionary
			if column == sort_column
				if "asc" == sort_direction
					anchor    += " \u2193"
					direction  = "desc"
				else
					anchor    += " \u2191"
					direction  = "asc"
				end
			end
		end

		link_to "(#{anchor})", { :sort_dictionary  => dictionary, 
			                     :sort_column      => column, 
			                     :sort_direction   => direction, 
			                   }
	end
end
