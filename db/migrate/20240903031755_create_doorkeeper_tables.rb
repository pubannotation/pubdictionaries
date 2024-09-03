# frozen_string_literal: true

class CreateDoorkeeperTables < ActiveRecord::Migration[7.0]
  def change
    create_table :oauth_access_tokens do |t|
      t.references :resource_owner, index: true
      t.string :token, null: false
      t.integer  :expires_in
      t.datetime :created_at, null: false
      t.datetime :revoked_at
    end

    add_index :oauth_access_tokens, :token, unique: true

    add_foreign_key :oauth_access_tokens, :users, column: :resource_owner_id
  end
end
