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
end

# add tags to dictionary
seed_tags = ['Giraffe', 'Tiger', 'Elephant'].map do |tag_value|
  dictionary.tags.find_or_create_by(value: tag_value)
end

# create entries for each mode
entry_items = [
  { mode: Entry::MODE_GRAY, label: "Gray Mode Entry", identifier: "1", tags: seed_tags },
  { mode: Entry::MODE_GRAY, label: "Gray Mode Entry2", identifier: "2", tags: [seed_tags.first, seed_tags.third] },
  { mode: Entry::MODE_WHITE, label: "White Mode Entry", identifier: "1", tags: seed_tags },
  { mode: Entry::MODE_WHITE, label: "White Mode Entry2", identifier: "2", tags: [seed_tags.third] },
  { mode: Entry::MODE_WHITE, label: "White Mode Entry3", identifier: "2", tags: [] },
  { mode: Entry::MODE_WHITE, label: "White Mode Entry4", identifier: "3", tags: [seed_tags.first, seed_tags.third] },
  { mode: Entry::MODE_WHITE, label: "White Mode Entry5", identifier: "4", tags: [] },
  { mode: Entry::MODE_BLACK, label: "Black Mode Entry", identifier: "3", tags: [seed_tags.second, seed_tags.third] },
  { mode: Entry::MODE_BLACK, label: "Black Mode Entry2", identifier: "1", tags: [] },
  { mode: Entry::MODE_AUTO_EXPANDED, label: "Auto Expanded Mode Entry", identifier: "1", tags: [seed_tags.second], score: 0.5 },
  { mode: Entry::MODE_AUTO_EXPANDED, label: "Auto Expanded Mode Entry2", identifier: "1", tags: [], score: 0.9999 },
  { mode: Entry::MODE_AUTO_EXPANDED, label: "Auto Expanded Mode Entry3", identifier: "3", tags: seed_tags, score: 0 },
]

entry_items.each do |entry_def|
  entry = dictionary.entries.find_or_create_by!(
    label: entry_def[:label],
    identifier: entry_def[:identifier],
    mode: entry_def[:mode],
    score: entry_def[:score]
  )

  entry.tags = entry_def[:tags]
end

# set entries_num
dictionary.update_entries_num
