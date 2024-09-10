class RemoveExpiredAtFromAccessTokens < ActiveRecord::Migration[7.0]
  def change
    remove_column :access_tokens, :expired_at, :datetime
  end
end
