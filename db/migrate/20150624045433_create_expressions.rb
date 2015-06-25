class CreateExpressions < ActiveRecord::Migration
  def change
    create_table :expressions do |t|
      t.string :words, unique: true

      t.timestamps
    end
  end
end
