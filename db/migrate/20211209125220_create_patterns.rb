class CreatePatterns < ActiveRecord::Migration[6.1]
  def change
    create_table :patterns do |t|
      t.string :expression
      t.string :identifier
      t.boolean :active, default:true
      t.references :dictionary, null: false, foreign_key: true

      t.timestamps
    end

    add_column :dictionaries, :patterns_num, :integer, default:0
  end
end
