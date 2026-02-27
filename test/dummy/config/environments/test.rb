Rails.application.configure do
  config.cache_classes = true
  config.eager_load = false
  config.serve_static_files = true
  config.public_file_server.headers = {
    'Cache-Control' => 'public, max-age=3600'
  }
  config.consider_all_requests_local = true
  config.action_dispatch
        .show_exceptions = :rescuable
end
