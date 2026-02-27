require 'ghostty_rails/channel/terminal_channel'
require 'ghostty_rails/engine'
require 'ghostty_rails/version'

module GhosttyRails
  class UnauthorizedError < StandardError; end

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

    # TERM environment variable passed to the PTY.
    attr_accessor :term_env

    # Seconds to wait for SIGTERM before SIGKILL.
    attr_accessor :kill_escalation_wait

    # Maximum scrollback buffer (sent to client).
    attr_accessor :scrollback

    def initialize
      @default_shell = ['bash', '--login']
      @kill_escalation_wait = 3
      @scrollback = 10_000
      @term_env = 'xterm-256color'
    end
  end
end
