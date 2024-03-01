class AddScoreToEntries < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :score, :decimal, precision: 5, scale: 4
  end
end
