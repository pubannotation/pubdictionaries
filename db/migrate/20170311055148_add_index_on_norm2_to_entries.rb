class AddIndexOnNorm2ToEntries < ActiveRecord::Migration[5.2]
  def change
    add_index :entries, :norm2
  end
end
