class RemoveLowercasedStemmedHyphenReplacedIssuesFromDictionaries < ActiveRecord::Migration
  def up
  	change_table :dictionaries do |t|
  		t.remove :lowercased
  		t.remove :stemmed
  		t.remove :hyphen_replaced
  		t.remove :issues
  	end
  end
  def down
  	change_table :dictionaries do |t|
  		t.boolean :lowercased
  		t.boolean :stemmed
  		t.boolean :hyphen_replaced
  		t.string  :issues
  	end
  end
end
