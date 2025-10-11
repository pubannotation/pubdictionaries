FactoryBot.define do
  factory :entry_tag do
    association :entry
    association :tag
  end
end
