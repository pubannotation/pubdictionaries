class AddContextFieldsToDictionary < ActiveRecord::Migration[8.0]
  def change
    add_column :dictionaries, :context, :text
    add_column :dictionaries, :context_embedding, :vector, limit: 768
    add_index :dictionaries, :context_embedding, using: :hnsw, opclass: :vector_cosine_ops
  end
end
