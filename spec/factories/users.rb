FactoryBot.define do
  factory :user do
    sequence(:username) { |n| "user#{n}" }
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }
    confirmed_at { Time.current }

    trait :admin do
      admin { true }
    end

    trait :unconfirmed do
      confirmed_at { nil }
    end
  end
end
