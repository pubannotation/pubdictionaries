class AccessToken < ApplicationRecord
  belongs_to :user

  def live?
    expired_at > Time.current
  end
end
