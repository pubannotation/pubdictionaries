FactoryGirl.define do
  factory :uri do |e|
    e.sequence(:resource){|n| "http://uri.ti/#{n}"}
  end
end
