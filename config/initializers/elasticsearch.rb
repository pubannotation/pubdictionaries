module PubDictionaries
  # Read settings per RAILS_ENV from a YAML file.
  # Set the setting values to the Rails.configuration so that it can be referred from application code.
  # For exapmle, you can get host of the elasticsearch from the `Rails.configuration.elasticsearch`.
  ELASTICSEARCH_CONFIG_FILE = 'config/elasticsearch.yml'
  Rails.configuration.elasticsearch = YAML.load_file(ELASTICSEARCH_CONFIG_FILE)[Rails.env].deep_symbolize_keys

  Elasticsearch::Model.client = Elasticsearch::Client.new Rails.configuration.elasticsearch
end

