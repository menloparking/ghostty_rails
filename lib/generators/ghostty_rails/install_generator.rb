require 'rails/generators'

module GhosttyRails
  module Generators
    # Installs GhosttyRails into a Rails app:
    #
    #   bin/rails generate ghostty_rails:install
    #
    # Creates:
    #   app/channels/terminal_channel.rb
    #   config/initializers/ghostty_rails.rb
    #
    # Also ensures ActionCable boilerplate files
    # exist (connection.rb, channel.rb, cable.yml).
    #
    # Prints post-install instructions for JS
    # setup, routes, and view integration.
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path(
        'install/templates', __dir__
      )

      desc 'Install GhosttyRails into your app'

      def ensure_action_cable
        connection = 'app/channels/' \
          'application_cable/connection.rb'
        unless File.exist?(
          File.join(destination_root, connection)
        )
          create_file connection, <<~RUBY
            module ApplicationCable
              class Connection < ActionCable::Connection::Base
              end
            end
          RUBY
        end

        channel = 'app/channels/' \
          'application_cable/channel.rb'
        unless File.exist?(
          File.join(destination_root, channel)
        )
          create_file channel, <<~RUBY
            module ApplicationCable
              class Channel < ActionCable::Channel::Base
              end
            end
          RUBY
        end

        cable_yml = 'config/cable.yml'
        unless File.exist?(
          File.join(destination_root, cable_yml)
        )
          create_file cable_yml, <<~YAML
            development:
              adapter: async

            test:
              adapter: test

            production:
              adapter: redis
              url: <%= ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" } %>
              channel_prefix: <%= Rails.application.class.module_parent_name.underscore %>_production
          YAML
        end
      end

      def create_channel
        template(
          'terminal_channel.rb.tt',
          'app/channels/terminal_channel.rb'
        )
      end

      def create_initializer
        template(
          'ghostty_rails.rb.tt',
          'config/initializers/ghostty_rails.rb'
        )
      end

      def print_post_install
        say ''
        say 'GhosttyRails installed!', :green
        say ''
        say 'Next steps:', :yellow
        say ''
        say '  1. Add the JS package:'
        say '     yarn add ghostty-rails'
        say ''
        say '  2. Register the Stimulus ' \
          'controllers in your ' \
          'app/javascript/application.ts:'
        say ''
        say '     import { ' \
          'TerminalController, ' \
          'TerminalFullscreenController ' \
          '} from "ghostty-rails"'
        say '     Stimulus.register(' \
          '"terminal", ' \
          'TerminalController)'
        say '     Stimulus.register(' \
          '"terminal-fullscreen", ' \
          'TerminalFullscreenController)'
        say ''
        say '  3. Add a route for your ' \
          'terminal page.'
        say ''
        say '  4. Edit ' \
          'app/channels/terminal_channel.rb ' \
          'to add your authorization logic.'
        say ''
      end
    end
  end
end
