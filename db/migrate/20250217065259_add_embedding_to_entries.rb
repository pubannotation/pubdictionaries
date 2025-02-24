class AddEmbeddingToEntries < ActiveRecord::Migration[8.0]
  def change
    add_column :entries, :embedding, :vector, limit: 4096 # dimensions
  end
end
