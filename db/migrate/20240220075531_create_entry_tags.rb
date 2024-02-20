class CreateEntryTags < ActiveRecord::Migration[7.0]
  def change
    create_table :entry_tags do |t|
      t.references :entry, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true

      t.timestamps
    end
  end
end
