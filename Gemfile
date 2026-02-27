source "https://rubygems.org"

gemspec

gem "rails", "~> 8.1"
gem "propshaft"
gem "pg"
gem "puma"
gem "solid_cable"

group :development, :test do
  gem "debug", platforms: %i[mri windows],
    require: "debug/prelude"
  gem "standard", require: false
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end
