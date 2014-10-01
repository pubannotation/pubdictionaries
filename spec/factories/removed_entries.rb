FactoryGirl.define do
  factory :removed_entry do |d|
    d.created_at 5.days.ago
    d.updated_at 5.days.ago
  end
end
