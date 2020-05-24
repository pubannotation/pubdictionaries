module DictionariesHelper
	def language_object(abbreviation)
		l = LanguageList::LanguageInfo.find(abbreviation)
		if l.nil?
			"unrecognizable: #{abbreviation}"
		else
			content_tag :div, id: 'language-' + abbreviation, class: 'language_object', title: "#{l.name} (ISO 639-1: #{l.iso_639_1}, ISO 639-3: #{l.iso_639_3})" do
				abbreviation
			end
		end
	end

end
