# frozen_string_literal: true

# Migration to remove the has_hnsw_index column which is no longer needed.
# Per-dictionary HNSW indexes on the main entries table were not effective
# because PostgreSQL preferred other indexes. Instead, we now use session-scoped
# temp tables with HNSW indexes for semantic search during text annotation.
class DropHasHnswIndexFromDictionaries < ActiveRecord::Migration[8.0]
  def change
    # Only remove if column exists (it may not exist in production)
    if column_exists?(:dictionaries, :has_hnsw_index)
      remove_column :dictionaries, :has_hnsw_index, :boolean, default: false, null: false
    end
  end
end
