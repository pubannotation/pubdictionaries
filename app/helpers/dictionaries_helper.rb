module DictionariesHelper
  def is_nil_or_empty?(value)
  	if value.nil? or value == ""
  	  return true
  	else
  	  return false
  	end
  end

  def format_dic_names(diclist_json)
    if diclist_json.nil?
      return ""
    else
      diclist = JSON.parse(diclist_json)
      ret_value = ""
      diclist.each do |dic_name|
        if ret_value == ""
          ret_value = dic_name
        else
          ret_value += "\n#{dic_name}"
        end
      end
      return ret_value
    end
  end

  def dictionary_status(dictionary)
    if dictionary.unfinished?
      css_class = 'unfinished_icon'
      title = 'Unfinished'
    else
      css_class = 'finished_icon'
      title = 'Finished'
    end
    content_tag :span, nil, class: css_class, title: title
  end

  def language_options
    I18nData.languages.invert.to_a
  end

  def language_name(abbreviation)
    I18nData.languages[abbreviation]
  end

  def language_object(abbreviation)
    content_tag :div, id: 'language-' + abbreviation, class: 'language_object', title: I18nData.languages[abbreviation] do
      abbreviation
    end
  end

end
