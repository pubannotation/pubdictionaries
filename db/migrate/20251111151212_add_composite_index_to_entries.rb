class AddCompositeIndexToEntries < ActiveRecord::Migration[8.0]
  def change
    # Add composite index for frequently used query pattern:
    # WHERE dictionary_id = ? AND norm2 = ? AND mode != ?
    #
    # This index significantly improves performance for the search_term queries
    # in Dictionary model which filter by dictionary_id, norm2, and exclude black entries
    #
    # Index columns ordered by:
    # 1. dictionary_id - High selectivity, always in WHERE clause
    # 2. norm2 - Medium selectivity, frequently queried
    # 3. mode - Low selectivity but used for filtering
    #
    # This covers queries like:
    # - entries.without_black.where(dictionary_id: X, norm2: Y)
    # - entries.where(dictionary_id: X, norm2: [Y1, Y2, ...]).where.not(mode: BLACK)
    add_index :entries,
              [:dictionary_id, :norm2, :mode],
              name: 'index_entries_on_dict_norm2_mode',
              comment: 'Composite index for dictionary search optimization'
  end
end
