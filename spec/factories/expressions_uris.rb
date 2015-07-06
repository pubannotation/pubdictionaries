FactoryGirl.define do
  factory :expressions_uri do |e|
    e.expression_id {|expression| expression.association(:expression)}
    e.uri_id {|uri| uri.association(:uri)}
    e.dictionary_id {|dictionary| dictionary.association(:dictionary)}
  end
end
