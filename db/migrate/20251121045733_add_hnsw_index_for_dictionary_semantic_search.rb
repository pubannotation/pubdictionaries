class AddHnswIndexForDictionarySemanticSearch < ActiveRecord::Migration[8.0]
  # This migration creates a partial HNSW index for semantic search
  # that only indexes searchable entries with non-null embeddings.
  #
  # The current global HNSW index (index_entries_on_embedding) indexes all entries,
  # but our queries always filter by:
  #   - dictionary_id (specific dictionary)
  #   - searchable = true
  #   - embedding IS NOT NULL
  #
  # By creating a partial index with WHERE conditions, PostgreSQL can use
  # the HNSW index more efficiently for vector similarity searches.
  #
  # Note: pgvector doesn't support composite indexes (dictionary_id, embedding),
  # but it does support partial indexes which can significantly reduce index size
  # and improve search performance by excluding non-searchable entries.

  def up
    # Remove the old global HNSW index
    remove_index :entries, name: :index_entries_on_embedding, if_exists: true

    # Create a partial HNSW index that only includes searchable entries with embeddings
    # This reduces index size and improves query performance
    execute <<~SQL
      CREATE INDEX index_entries_on_embedding_searchable
      ON entries
      USING hnsw (embedding vector_cosine_ops)
      WHERE searchable = true AND embedding IS NOT NULL;
    SQL

    # Add comment to index for documentation
    execute <<~SQL
      COMMENT ON INDEX index_entries_on_embedding_searchable IS
      'Partial HNSW index for semantic search - only indexes searchable entries with embeddings';
    SQL
  end

  def down
    # Remove the partial index
    execute <<~SQL
      DROP INDEX IF EXISTS index_entries_on_embedding_searchable;
    SQL

    # Restore the original global HNSW index
    add_index :entries, :embedding, using: :hnsw, opclass: :vector_cosine_ops, name: :index_entries_on_embedding
  end
end
