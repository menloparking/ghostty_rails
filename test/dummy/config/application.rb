require_relative "boot"
require "rails"
require "action_controller/railtie"
require "action_cable/engine"
require "active_job/railtie"
require "rails/test_unit/railtie"

module Dummy
  class Application < Rails::Application
    config.load_defaults 8.0
    config.eager_load = false
    config.serve_static_files = true
    config.secret_key_base = "test-secret-" \
      "ghostty-rails-dummy-app-key-base"
    config.hosts << "127.0.0.1"
    config.hosts << "localhost"

    config.root = File.expand_path("..", __dir__)

    # ActionCable in async mode for tests
    config.action_cable.url = "/cable"
    config.action_cable
      .disable_request_forgery_protection = true
  end
end
