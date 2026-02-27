require 'action_cable'
require 'ghostty_rails/channel/terminal_channel'
require 'ghostty_rails/engine'
require 'ghostty_rails/version'

module GhosttyRails
  class UnauthorizedError < StandardError; end
  class RateLimitedError < StandardError; end

  class << self
    # Optional global configuration block.
    #
    #   GhosttyRails.configure do |config|
    #     config.default_shell = ["/bin/zsh"]
    #   end
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Configuration.new
    end
  end

  class Configuration
    # The command spawned for local terminal
    # sessions. Override per-app if bash is not
    # the desired default.
    attr_accessor :default_shell

    # Seconds to wait for SIGTERM before SIGKILL.
    attr_accessor :kill_escalation_wait

    # Maximum concurrent terminal sessions per
    # connection. nil means unlimited.
    attr_accessor :max_sessions

    # When true (the default), the base channel
    # rejects subscriptions in production unless
    # authorize_terminal! is overridden. In
    # development and test it logs a warning but
    # permits the connection.
    attr_accessor :require_explicit_authorization

    # Maximum new sessions allowed within
    # rate_limit_period seconds per connection
    # identifier. nil means no rate limiting.
    attr_accessor :rate_limit

    # Sliding window in seconds for rate limiting.
    # Defaults to 60.
    attr_accessor :rate_limit_period

    # Maximum scrollback buffer (sent to client).
    attr_accessor :scrollback

    # TERM environment variable passed to the PTY.
    attr_accessor :term_env

    def initialize
      @default_shell = ['bash', '--login']
      @kill_escalation_wait = 3
      @max_sessions = nil
      @rate_limit = nil
      @rate_limit_period = 60
      @require_explicit_authorization = true
      @scrollback = 10_000
      @term_env = 'xterm-256color'
    end
  end
end
