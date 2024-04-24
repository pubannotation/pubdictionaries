ActiveRecord::Base.transaction do
  # user settings
  user = User.find_or_create_by(email: 'test@pubdictionaries.org') do |user|
    user.username = 'pub dic person'
    user.password = 'password'
    user.confirmed_at = Time.now
  end

  # create dictionary
  dictionary = user.dictionaries.find_or_create_by(name: 'EntrezGene') do |dictionary|
    dictionary.description = 'EntrezGene dictionary'
    dictionary.public = true
    dictionary.associated_annotation_project = 'aaa_project'
  end

  # add tags to dictionary
  seed_tags = ['Giraffe', 'Tiger', 'Elephant'].map do |tag_value|
    dictionary.tags.find_or_create_by(value: tag_value)
  end

  # create entries for each mode
  entry_items = [
    { mode: EntryMode::GRAY, label: "Gray Mode Entry", identifier: "1", norm2: nil, dirty: false, tags: seed_tags },
    { mode: EntryMode::GRAY, label: "Gray Mode Entry2", identifier: "2", norm2: nil, dirty: false, tags: [seed_tags.first, seed_tags.third] },
    { mode: EntryMode::WHITE, label: "White Mode Entry", identifier: "1", norm2: "test", dirty: true, tags: seed_tags },
    { mode: EntryMode::WHITE, label: "White Mode Entry2", identifier: "2", norm2: "test", dirty: true, tags: [seed_tags.third] },
    { mode: EntryMode::WHITE, label: "White Mode Entry3", identifier: "2", norm2: nil, dirty: true, tags: [] },
    { mode: EntryMode::WHITE, label: "White Mode Entry4", identifier: "3", norm2: nil, dirty: false, tags: [seed_tags.first, seed_tags.third] },
    { mode: EntryMode::WHITE, label: "White Mode Entry5", identifier: "4", norm2: nil, dirty: false, tags: [] },
    { mode: EntryMode::BLACK, label: "Black Mode Entry", identifier: "3", norm2: nil, dirty: false, tags: [seed_tags.second, seed_tags.third] },
    { mode: EntryMode::BLACK, label: "Black Mode Entry2", identifier: "1", norm2: nil, dirty: false, tags: [] },
    { mode: EntryMode::AUTO_EXPANDED, label: "Auto Expanded Mode Entry", identifier: "1", norm2: nil, dirty: false, tags: [seed_tags.second], score: 0.5 },
    { mode: EntryMode::AUTO_EXPANDED, label: "Auto Expanded Mode Entry2", identifier: "1", norm2: nil, dirty: false, tags: [], score: 0.9999 },
    { mode: EntryMode::AUTO_EXPANDED, label: "Auto Expanded Mode Entry3", identifier: "3", norm2: nil, dirty: false, tags: seed_tags, score: 0 },
  ]

  entry_items.each do |entry_def|
    entry = dictionary.entries.find_or_create_by!(
      label: entry_def[:label],
      norm1: Dictionary.normalize1(entry_def[:label]),
      norm2: entry_def[:norm2],
      identifier: entry_def[:identifier],
      mode: entry_def[:mode],
      score: entry_def[:score],
      dirty: entry_def[:dirty]
    )

    entry.tags = entry_def[:tags]
  end

  # set entries_num
  dictionary.update_entries_num
end
