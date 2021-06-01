class ActiveRecord::Base
  Faker::Config.locale = :en if Rails.env.development?

  DummyCount = 100

  def self.generate_dummy_expressions
    DummyCount.times do
      words = Faker::Commerce::product_name.downcase
      date_time = DateTime.now.strftime("%Y-%m-%d %H:%M:%S")
      sql = "INSERT INTO expressions(words, created_at, updated_at, dictionaries_count) VALUES ('#{words}', '#{date_time}', '#{date_time}', 1)"
      self.connection.insert_sql(sql)

      uri = Faker::Internet::url
      sql = "INSERT INTO uris(resource, created_at, updated_at, dictionaries_count) VALUES ('#{uri}', '#{date_time}', '#{date_time}', 1)"
      self.connection.insert_sql(sql)

      dictionary_id = 12
      sql = "INSERT INTO expressions_uris(expression_id, uri_id, dictionary_id, created_at, updated_at) VALUES (#{Expression.last.id}, #{Uri.last.id}, #{dictionary_id}, '#{date_time}', '#{date_time}')"
      self.connection.insert_sql(sql)
    end
  end
end
