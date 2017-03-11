class AddIndexOnNorm2ToEntries < ActiveRecord::Migration
  def change
    add_index :entries, :norm2
  end
end
