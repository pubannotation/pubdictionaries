class AccessToken < ApplicationRecord
  belongs_to :user
  before_create :set_token

  private

  def set_token
    self.token = SecureRandom.hex(16)
  end
end
