class RenameEntriesToPairs < ActiveRecord::Migration
  def change
    rename_table :entries, :pairs
  end 
end
