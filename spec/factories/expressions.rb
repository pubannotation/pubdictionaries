FactoryGirl.define do
  factory :expression do |e|
    e.sequence(:words){|n| "words #{n}"}
  end
end
