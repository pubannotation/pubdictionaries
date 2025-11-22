FactoryBot.define do
  factory :entry do
    sequence(:label) { |n| "test label #{n}" }
    sequence(:identifier) { |n| "TEST:#{n.to_s.rjust(6, '0')}" }
    norm1 { label.downcase }
    norm2 { label.downcase.gsub(/\s+/, ' ').strip }
    label_length { label.length }
    mode { EntryMode::GRAY }
    dirty { false }
    searchable { true }
    association :dictionary

    trait :gray do
      mode { EntryMode::GRAY }
    end

    trait :white do
      mode { EntryMode::WHITE }
    end

    trait :black do
      mode { EntryMode::BLACK }
    end

    trait :auto_expanded do
      mode { EntryMode::AUTO_EXPANDED }
      score { 0.85 }
    end

    trait :dirty do
      dirty { true }
    end

    trait :with_tags do
      transient do
        tag_count { 2 }
      end

      after(:create) do |entry, evaluator|
        create_list(:tag, evaluator.tag_count, dictionary: entry.dictionary).each do |tag|
          create(:entry_tag, entry: entry, tag: tag)
        end
      end
    end
  end
end
