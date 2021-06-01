class CreateAssociations < ActiveRecord::Migration[5.2]
  def change
    create_table :associations do |t|
      t.references :user
      t.references :dictionary

      t.timestamps
    end
  end
end
