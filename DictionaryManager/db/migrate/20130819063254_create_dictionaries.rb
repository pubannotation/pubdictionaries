class CreateDictionaries < ActiveRecord::Migration
  def self.up
    create_table :dictionaries do |t|
      t.string :title
      t.string :creator
      t.text :description

      t.timestamps
    end
  end

  def self.down
    drop_table :dictionaries 
  end
end
