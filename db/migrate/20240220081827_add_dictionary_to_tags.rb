class AddDictionaryToTags < ActiveRecord::Migration[7.0]
  def change
    add_reference :tags, :dictionary, null: false, foreign_key: true
  end
end
