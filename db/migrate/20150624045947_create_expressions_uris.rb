class CreateExpressionsUris < ActiveRecord::Migration
  def change
    create_table :expressions_uris do |t|
      t.integer :expression_id
      t.integer :uri_id
      t.integer :dictionary_id

      t.timestamps
    end

    add_index(:expressions_uris, [:expression_id, :uri_id, :dictionary_id], unique: true, name: 'index_exp_uri_dic')
  end
end
