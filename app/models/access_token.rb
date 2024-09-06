class AccessToken < ApplicationRecord
  belongs_to :user

  def self.find_token(headers)
    bearer_token = bearer_token_in(headers)
    find_by(token: bearer_token) if bearer_token
  end

  def live?
    expired_at > Time.current
  end

  private

  def self.bearer_token_in(headers)
    case headers['Authorization']
    in /^Bearer (.+)$/
      Regexp.last_match(1)
    else
      nil
    end
  end
end
