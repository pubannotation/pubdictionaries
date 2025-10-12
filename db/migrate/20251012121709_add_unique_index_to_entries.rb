class AddUniqueIndexToEntries < ActiveRecord::Migration[8.0]
  def change
    # Remove existing non-unique index
    remove_index :entries, name: "index_entries_on_dictionary_id_and_label_and_identifier"

    # Add unique index to prevent duplicate entries
    add_index :entries, [:dictionary_id, :label, :identifier],
              unique: true,
              name: "index_entries_on_dictionary_id_and_label_and_identifier_unique"
  end
end
