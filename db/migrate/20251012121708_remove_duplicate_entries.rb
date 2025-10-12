class RemoveDuplicateEntries < ActiveRecord::Migration[8.0]
  def up
    # Find and remove duplicate entries, keeping the oldest one
    execute <<-SQL
      DELETE FROM entry_tags
      WHERE entry_id IN (
        SELECT e2.id
        FROM entries e1
        INNER JOIN entries e2 
          ON e1.dictionary_id = e2.dictionary_id 
          AND e1.label = e2.label 
          AND e1.identifier = e2.identifier
          AND e1.id < e2.id
      )
    SQL

    execute <<-SQL
      DELETE FROM entries
      WHERE id IN (
        SELECT e2.id
        FROM entries e1
        INNER JOIN entries e2 
          ON e1.dictionary_id = e2.dictionary_id 
          AND e1.label = e2.label 
          AND e1.identifier = e2.identifier
          AND e1.id < e2.id
      )
    SQL
  end

  def down
    # Cannot restore deleted duplicates
    raise ActiveRecord::IrreversibleMigration
  end
end
