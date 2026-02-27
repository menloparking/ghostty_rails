require 'minitest/autorun'
require 'action_cable'
require 'action_cable/channel/test_case'
require 'ghostty_rails'

# Minimal Rails.logger for tests
unless defined?(Rails)
  module Rails
    def self.logger
      @logger ||= Logger.new($stdout,
                             level: Logger::WARN)
    end
  end
end
