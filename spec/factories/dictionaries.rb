FactoryBot.define do
  factory :dictionary do
    sequence(:name) { |n| "test_dictionary_#{n}" }
    description { "Test dictionary description" }
    association :user
    public { false }
    entries_num { 0 }
    threshold { 0.85 }
    language { nil }

    trait :public do
      public { true }
    end

    trait :with_language do
      language { "eng" }
    end

    trait :korean do
      language { "kor" }
    end

    trait :japanese do
      language { "jpn" }
    end
  end
end
