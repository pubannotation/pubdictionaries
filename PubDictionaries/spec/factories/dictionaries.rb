FactoryGirl.define do
  factory :dictionary do |d|
    d.sequence(:creator){|n| "Creator #{n}"}
    d.sequence(:title){|n| "Title #{n}"}
    d.description 'Desctription of dictionary'
    d.file 'file'
  end
end
