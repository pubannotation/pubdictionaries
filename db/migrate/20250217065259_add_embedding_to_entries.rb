class AddEmbeddingToEntries < ActiveRecord::Migration[8.0]
  def change
    add_column :entries, :embedding, :vector, limit: 768 # dimensions
    add_index :entries, :embedding, using: :hnsw, opclass: :vector_cosine_ops
  end
end
