class AccessToken < ApplicationRecord
  belongs_to :user

  def unexpired?
    expired_at > Time.current
  end
end
