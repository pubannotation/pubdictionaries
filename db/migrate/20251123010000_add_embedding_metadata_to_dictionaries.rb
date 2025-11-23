class AddEmbeddingMetadataToDictionaries < ActiveRecord::Migration[7.1]
  def change
    add_column :dictionaries, :embedding_model, :string
    add_column :dictionaries, :embedding_report, :jsonb
  end
end
