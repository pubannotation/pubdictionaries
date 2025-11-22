class AddHasSemanticTableToDictionaries < ActiveRecord::Migration[8.0]
  def change
    add_column :dictionaries, :has_semantic_table, :boolean, default: false, null: false
  end
end
