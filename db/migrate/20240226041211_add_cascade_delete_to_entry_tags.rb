class AddCascadeDeleteToEntryTags < ActiveRecord::Migration[7.0]
  def change
    remove_foreign_key :entry_tags, :entries

    add_foreign_key :entry_tags, :entries, on_delete: :cascade
  end
end
