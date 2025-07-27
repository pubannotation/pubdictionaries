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
    content_tag(:p, link_to(message, show_patterns_dictionary_path(@dictionary)), class: 'page_link')
  end

  def num_entries_helper
    content_tag(:span, number_with_delimiter(@dictionary.entries_num, :delimiter => ',') + ' entries', class: 'num_entries')
  end

  def downloadable_helper
    if @dictionary.large?
      if @dictionary.creating_downloadable?
        content_tag(:i, '', class:"fa fa-hourglass", title: "Downloadable under preparation")
      elsif @dictionary.downloadable_updatable?
        link_to(content_tag(:i, '', class:"fa fa-download"), create_downloadable_dictionary_path(@dictionary), method: :post, title: "Download")
      else
        link_to(content_tag(:i, '', class:"fa fa-download"), downloadable_dictionary_path(@dictionary), title: "Download")
      end
    else
      link_to(content_tag(:i, '', class:"fa fa-download"), params.permit(:mode).merge(mode: EntryMode::ACTIVE, format: :tsv), title: "Download")
    end
  end

  def upload_entries_helper
    if @dictionary.jobs.count == 0
      link_to(content_tag(:i, '', class:"fa fa-upload"), upload_entries_dictionary_path(@dictionary.name), title: "Upload")
    else
      link_to(content_tag(:i, '', class:"fa fa-cog fa-spin"), upload_entries_dictionary_path(@dictionary.name), title: "Upload")
    end
  end

  def unstable_icon_helper
    content_tag(:i, '', class:"fa fa-cog fa-spin", title: 'The dictionary is currently undergoing updates.')
  end

  def job_stop_helper(job)
    if job.running?
      button_to('Stop', stop_dictionary_job_path(@dictionary.name, job.id), :method => :put, data: { confirm: 'Are you sure?' }, class: :button, disabled: job.suspended?)
    end
  end

  def delete_entries_helper(mode = nil)
    mode_to_s = EntryMode.to_s(mode)

    title = if mode == EntryMode::BLACK
      "Turn all the black entries to gray"
    else
      "Delete all the #{mode_to_s} entries"
    end

    unless @dictionary.jobs.count == 0
      title += ' (Disabled due to remaining task)'
    end

    confirm = if mode == EntryMode::BLACK
      "Are you sure to turn all the black entries to gray?"
    else
      "Are you sure to delete all the #{mode_to_s} entries?"
    end

    link_to_if @dictionary.jobs.count == 0,
      content_tag(:i, '', class:"fa-regular fa-trash-can fa-lg", title: title),
      empty_dictionary_entries_path(@dictionary, mode:mode),
      method: :put,
      data: {confirm: confirm}
  end

  def destroy_dictionary_helper
    title = 'Delete the dictionary'
    unless @dictionary.jobs.count == 0
      title += ' (Disabled due to remaining task)'
    end

    link_to_if @dictionary.jobs.count == 0,
      content_tag(:i, '', class:"fa fa-bomb fa-lg", title: title),
      @dictionary,
      method: :delete,
      data: {confirm: 'Are you sure to completely delete this dictionary?'}
  end

  def badge_embedding(project)
    badge, btitle = if project.embeddings_populated?
      ['<i class="fa fa-snowflake-o" aria-hidden="true"></i>', 'Embeddings are ready']
    else
      ['<i class="fa fa-bars" aria-hidden="true"></i>', 'Embeddings are not ready']
    end

    badge.present? ? "<span class='badge' title='#{btitle}'>#{badge}</span>" : ""
  end

end
