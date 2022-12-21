# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
Rails.application.config.filter_parameters += [:password]

# filter out long text parameters
Rails.application.config.filter_parameters << lambda do |k, v|
  if k == 'text' && v && v.class == String && v.length > 64
    v.replace(v[0, 60] + ' ...')
  end
end
