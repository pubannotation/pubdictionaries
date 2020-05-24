class DropLanguages < ActiveRecord::Migration[5.2]
  def up
    drop_table :dl_associations
    drop_table :languages
  end

  def down
    create_table :languages do |t|
      t.string :name
      t.string :abbreviation
    end
    create_table :dl_associations do |t|
      t.references :dictionary
      t.references :language
    end
  end
end
