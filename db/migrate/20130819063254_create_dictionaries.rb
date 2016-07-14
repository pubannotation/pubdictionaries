class CreateDictionaries < ActiveRecord::Migration
  def change
    create_table :dictionaries do |t|
      t.string :name
      t.text :description
      t.references :user
      t.string :language
      t.boolean :active, default: true
      t.timestamps
    end

  end
end
