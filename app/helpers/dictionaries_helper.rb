module DictionariesHelper
  def language_options
    I18nData.languages.invert.to_a
  end

  def language_object(abbreviation)
    content_tag :div, id: 'language-' + abbreviation, class: 'language_object', title: I18nData.languages[abbreviation] do
      abbreviation
    end
  end

end
