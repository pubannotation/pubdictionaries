class CreateDlAssociations < ActiveRecord::Migration
  def change
    create_table :dl_associations do |t|
      t.references :dictionary
      t.references :language
    end
    add_index :dl_associations, :dictionary_id
    add_index :dl_associations, :language_id
  end
end
