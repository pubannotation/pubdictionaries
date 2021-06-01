class CreateDictionaries < ActiveRecord::Migration[5.2]
  def change
    create_table :dictionaries do |t|
      t.string :name
      t.text :description, default: ''
      t.references :user
      t.integer :entries_num, default:0
      t.timestamps
    end

  end
end
