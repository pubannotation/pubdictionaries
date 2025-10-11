FactoryBot.define do
  factory :tag do
    sequence(:value) { |n| "tag#{n}" }
    association :dictionary

    trait :disease do
      value { "disease" }
    end

    trait :protein do
      value { "protein" }
    end

    trait :gene do
      value { "gene" }
    end
  end
end
