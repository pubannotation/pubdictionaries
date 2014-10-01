FactoryGirl.define do
  factory :user do |u|
    u.sequence(:email){|n| "mail-#{n}@mail.factory"}
    u.created_at 5.days.ago
    u.updated_at 5.days.ago
    u.password "password"
  end
end
