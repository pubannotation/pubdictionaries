# user settings
user = User.find_by(email: 'test@pubdictionaries.org')
unless user
  user = User.create!(
            username: 'pub dic person',
            email: 'test@pubdictionaries.org',
            password: 'password',
            confirmed_at: Time.now
          )
end

# create dictionary
dictionary = Dictionary.find_by(name: 'EntrezGene')
unless dictionary
  dictionary = user.dictionaries.create!(
          name: 'EntrezGene',
          description: 'EntrezGene dictionary',
          public: true
        )

  # add tags to dictionary
  tags = ["Giraffe", "Tiger", "Elephant"].each do |tag_value|
    Tag.create!(value: tag_value, dictionary: dictionary)
  end
end

# create entries for each mode
entry_items = [
  { mode: Entry::MODE_GRAY, label: "Gray Mode Entry", identifier: "1", tag_ids: [1, 2, 3]},
  { mode: Entry::MODE_GRAY, label: "Gray Mode Entry2", identifier: "2", tag_ids: [1, 3] },
  { mode: Entry::MODE_WHITE, label: "White Mode Entry", identifier: "1", tag_ids: [1, 2, 3] },
  { mode: Entry::MODE_WHITE, label: "White Mode Entry2", identifier: "2", tag_ids: [1] },
  { mode: Entry::MODE_WHITE, label: "White Mode Entry3", identifier: "2", tag_ids: [] },
  { mode: Entry::MODE_WHITE, label: "White Mode Entry4", identifier: "3", tag_ids: [1, 2] },
  { mode: Entry::MODE_WHITE, label: "White Mode Entry5", identifier: "4", tag_ids: [] },
  { mode: Entry::MODE_BLACK, label: "Black Mode Entry", identifier: "3", tag_ids: [2, 3] },
  { mode: Entry::MODE_BLACK, label: "Black Mode Entry2", identifier: "1", tag_ids: [] },
  { mode: Entry::MODE_AUTO_EXPANDED, label: "Auto Expanded Mode Entry", identifier: "1", tag_ids: [2] },
  { mode: Entry::MODE_AUTO_EXPANDED, label: "Auto Expanded Mode Entry2", identifier: "1", tag_ids: [] },
  { mode: Entry::MODE_AUTO_EXPANDED, label: "Auto Expanded Mode Entry3", identifier: "3", tag_ids: [1, 2, 3] }
]

entries = []
entry_items.each do |entry|
  created_entry = dictionary.entries.find_or_create_by!(
              label: entry[:label],
              identifier: entry[:identifier],
              mode: entry[:mode],
            )

  if entry[:tag_ids].present?
    entry[:tag_ids].each do |tag_id|
      created_entry.entry_tags.find_or_create_by!(tag_id: tag_id)
    end
  end
end

# set entries_num
num_gray = dictionary.entries.where(mode: Entry::MODE_GRAY).count
num_white = dictionary.entries.where(mode: Entry::MODE_WHITE).count
dictionary.update(entries_num: (num_gray + num_white))
