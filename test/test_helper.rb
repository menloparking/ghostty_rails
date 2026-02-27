# Boot the dummy Rails app so ActionCable's test
# infrastructure has a proper pubsub adapter config
# (cable.yml adapter: async).
ENV["RAILS_ENV"] = "test"
require_relative "dummy/config/environment"

require "rails/test_help"
require "action_cable/channel/test_case"
