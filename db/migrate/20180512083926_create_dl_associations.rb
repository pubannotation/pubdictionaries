class CreateDlAssociations < ActiveRecord::Migration[5.2]
  def change
    create_table :dl_associations do |t|
      t.references :dictionary
      t.references :language
    end
  end
end
