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

	def simple_paginate
		current_page = params[:page].nil? ? 1 : params[:page].to_i
		nav = ''
		nav += link_to(content_tag(:i, '', class: "fa fa-angle-double-left", "aria-hidden" => "true"), params.permit(:mode, :controller, :action, :id, :label_search, :id_search, :page, :per).except(:page), title: "First", class: 'page') if current_page > 2
		nav += link_to(content_tag(:i, '', class: "fa fa-angle-left", "aria-hidden" => "true"), params.permit(:mode, :controller, :action, :id, :label_search, :id_search, :page, :per).merge(page: current_page - 1), title: "Previous", class: 'page') if current_page > 1
		nav += content_tag(:span, "Page #{current_page}", class: 'page')
		nav += link_to(content_tag(:i, '', class: "fa fa-angle-right", "aria-hidden" => "true"), params.permit(:mode, :controller, :action, :id, :label_search, :id_search, :page, :per).merge(page: current_page + 1), title: "Next", class: 'page') unless params[:last_page]
		content_tag(:nav, nav.html_safe, class: 'pagination')
	end

	def link_to_patterns
		count = @dictionary.patterns.count
		message = if count > 1
			"There are #{count} pattern entries."
		else
			"There is #{count} pattern entry."
		end
		link_to(content_tag(:p, message, class: 'page_link'), show_patterns_dictionary_path(@dictionary))
	end

	def downloadable_helper
		if @dictionary.large?
			if @dictionary.creating_downloadable?
				content_tag(:i, '', class:"fa fa-hourglass", title: "Downloadable under preparation")
			elsif @dictionary.downloadable_updatable?
				link_to(content_tag(:i, '', class:"fa fa-download"), create_downloadable_dictionary_path(@dictionary), method: :post, title: "Download 2")
			else
				link_to(content_tag(:i, '', class:"fa fa-download"), downloadable_dictionary_path(@dictionary), title: "Download 3")
			end
		else
			link_to(content_tag(:i, '', class:"fa fa-download"), params.permit(:mode).merge(mode: Entry::MODE_ACTIVE, format: :tsv), title: "Download 4")
		end
	end
end
