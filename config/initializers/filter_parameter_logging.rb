# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn
]

# filter out long text parameters
Rails.application.config.filter_parameters << lambda do |k, v|
  if k == 'text' && v && v.class == String && v.length > 64
    v.replace(v[0, 60] + ' ...')
  end
end
