module GhosttyRails
  class Engine < ::Rails::Engine
    isolate_namespace GhosttyRails

    initializer 'ghostty_rails.assets' do |app|
      app.config.assets.paths <<
        root.join('app', 'assets', 'javascripts')
    end
  end
end
