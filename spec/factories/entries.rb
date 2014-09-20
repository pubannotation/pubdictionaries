FactoryGirl.define do
  factory :entry do |d|
    d.uri 'http://uri.to'
    d.label 'label'
    d.view_title 'view_title'
    d.search_title 'search_title'
  end
end
