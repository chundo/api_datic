source "https://rubygems.org"

ruby "3.2.6"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.1"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

gem "websocket-client-simple"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# BDs
gem "pg"
gem "sidekiq"
gem "redis"

# Scraping Tools
gem "ferrum"
gem "uri"
gem "open-uri"
gem "nokogiri"
gem "httparty"
gem "icalendar"
gem "binance-connector-ruby"
gem "shopify_api"

# Tools
# gem "ruby-openai"
gem "openai", "~> 0.15.0"
# gem 'dotenv-rails', groups: %i[development test]
gem "rack-attack"
gem "config"
gem "rack-cors"
gem "ffmpeg", git: "https://github.com/instructure/ruby-ffmpeg"
gem "icalendar"
gem "roo"
gem "docx"

# AWS Tools
# gem "aws-sdk-s3"
# gem 'aws-sdk', '~> 3'
gem "aws-sdk-core"
gem "aws-sdk", "~> 3"
gem "aws-sdk-s3", require: false

gem "letter_opener", group: :development
gem "letter_opener_web", "~> 2.0", group: :development

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
# gem "rack-cors"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "byebug"
  gem "dotenv-rails"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end
