class AddSearchableToEntries < ActiveRecord::Migration[8.0]
  def up
    # Add searchable column with default true
    add_column :entries, :searchable, :boolean, default: true, null: false

    # Add compound index for efficient filtering with partial index
    # Only index searchable=true entries to save space
    add_index :entries, [:dictionary_id, :searchable],
              where: "searchable = true",
              name: "index_entries_on_dictionary_id_and_searchable"

    # Backfill existing entries to searchable=true
    # This happens automatically due to default: true
    say "Searchable column added with default=true for all entries"
  end

  def down
    remove_index :entries, name: "index_entries_on_dictionary_id_and_searchable"
    remove_column :entries, :searchable
  end
end
