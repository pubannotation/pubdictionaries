source 'https://rubygems.org'

gem 'rails', '3.2.16'
gem 'activerecord-import', '~> 0.3.1'
gem 'libv8'

gem 'stemmify'
gem 'sequel'
gem 'triez'

# gem 'sqlite3'
gem 'pg', :require => 'pg'   # Use PostgreSQL
gem 'wice_grid'              # Grid viewer for tab-separated data view.
gem 'colorbox-rails'         # Popup lightbox for selecting dictionaries.
gem 'font-awesome-sass'
gem 'jquery-rails', '>3.0.0' # Jquery.
gem 'jquery-ui-rails'        # Jquery.
gem 'devise', '3.0.3'
gem 'rest-client'
gem 'zeroclipboard-rails'
gem 'delayed_job_active_record'
gem 'daemons'
gem 'kaminari'
gem 'elasticsearch-model'
gem 'elasticsearch-rails'
gem 'rails-jquery-autocomplete'
# gem 'jquery-rails', "<3.0.0"
# gem 'will_paginate', '>= 3.0.pre'     # Not compatible with Wice_Grid

group :development, :test do
  gem 'rspec-rails', '~> 2.0'
end

group :development do
  gem 'guard-livereload', require: false
  gem 'faker'
  gem 'rails-erd'
end

group :test do
  gem 'spork-rails'
  gem 'factory_girl_rails'
  gem 'simplecov', :require => false
  gem 'capybara'
  gem 'test-unit'
end

group :production do
 gem 'thin'
 
 # Use unicorn as the app server
 gem 'unicorn'
end

# Bundle edge Rails instead:
# gem 'rails', :git => 'git://github.com/rails/rails.git'

# Gems used only for assets and not required
# in production environments by default.
group :assets do
  gem 'sass-rails',   '~> 3.2.3'
  gem 'coffee-rails', '~> 3.2.1'

  # See https://github.com/sstephenson/execjs#readme for more supported runtimes
  gem 'therubyracer', :platforms => :ruby

  # gem 'uglifier', '>= 1.0.3'
  gem 'uglifier'
end

# To use ActiveModel has_secure_password
# gem 'bcrypt-ruby', '~> 3.0.0'

# To use Jbuilder templates for JSON
# gem 'jbuilder'

# To use debugger
# gem 'debugger'
