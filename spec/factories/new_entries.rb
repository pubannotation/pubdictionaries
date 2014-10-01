FactoryGirl.define do
  factory :new_entry do |d|
    d.uri 'http://new.to'
    d.label 'new_label'
    d.view_title 'new_view_title'
    d.search_title 'new_search_title'
  end
end
