# Boots the dummy Rails app in a child process,
# opens it in headless Chrome via Selenium, waits
# for the stub terminal to render, and saves a
# screenshot to doc/screenshot.png.
#
# Usage:
#   bundle exec rake screenshot
#
# Requirements (development only):
#   - capybara and selenium-webdriver in Gemfile
#   - Chrome or Chromium on $PATH
desc 'Take a screenshot of the dummy terminal app'
task :screenshot do
  require 'socket'
  require 'selenium-webdriver'
  require 'fileutils'

  gem_root = File.expand_path('../..', __dir__)
  dummy_env = File.join(
    gem_root,
    'test/dummy/config/environment.rb'
  )
  out_dir = File.join(gem_root, 'doc')
  out_path = File.join(out_dir, 'screenshot.png')
  port = find_free_port

  server_script = <<~RUBY
    require_relative "#{dummy_env}"
    require "rack/handler/puma"

    Rack::Handler::Puma.run(
      Rails.application,
      Host: "127.0.0.1",
      Port: #{port},
      Silent: true,
      Threads: "1:2"
    )
  RUBY

  server_pid = spawn(
    {
      'RAILS_ENV' => 'test',
      'BUNDLE_GEMFILE' => File.join(
        gem_root, 'Gemfile'
      )
    },
    RbConfig.ruby, '-e', server_script,
    out: File::NULL,
    err: File::NULL
  )

  wait_for_server('127.0.0.1', port, timeout: 15)
  puts "Dummy app running on port #{port}"

  begin
    options =
      Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--headless=new')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-gpu')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--window-size=1280,800')
    options.add_argument(
      '--force-device-scale-factor=2'
    )

    driver = Selenium::WebDriver.for(
      :chrome, options: options
    )
    driver.navigate.to(
      "http://127.0.0.1:#{port}/terminal"
    )

    # Wait for the stub terminal div to appear.
    # The dummy layout loads Stimulus from a CDN,
    # so allow extra time for the network fetch.
    wait = Selenium::WebDriver::Wait.new(
      timeout: 20
    )
    wait.until do
      driver.find_element(
        css: '[data-stub-terminal]'
      )
    rescue Selenium::WebDriver::Error::NoSuchElementError
      false
    end

    # Let CSS transitions settle
    sleep 0.5

    FileUtils.mkdir_p(out_dir)
    raw_path = File.join(out_dir, 'screenshot_raw.png')
    driver.save_screenshot(raw_path)

    # Crop to just the terminal element using
    # its bounding rect (2x for device scale).
    rect = driver.execute_script(<<~JS)
      const el = document.getElementById(
        "terminal-page"
      );
      const r = el.getBoundingClientRect();
      return {
        x: Math.round(r.x * 2),
        y: Math.round(r.y * 2),
        w: Math.round(r.width * 2),
        h: Math.round(r.height * 2)
      };
    JS

    crop = "#{rect['w']}x#{rect['h']}" \
           "+#{rect['x']}+#{rect['y']}"
    system(
      'magick', raw_path,
      '-crop', crop, '+repage',
      # The page background (#f5f5f5) peeks
      # through the CSS border-radius corners.
      # Knock it out to transparent alpha.
      '-fuzz', '3%',
      '-transparent', '#f5f5f5',
      out_path
    )
    File.delete(raw_path)
    puts "Screenshot saved to #{out_path}"
  ensure
    driver&.quit
    Process.kill('TERM', server_pid)
    Process.waitpid(server_pid)
  end
end

def find_free_port
  server = TCPServer.new('127.0.0.1', 0)
  port = server.addr[1]
  server.close
  port
end

def wait_for_server(host, port, timeout: 15)
  deadline = Process.clock_gettime(
    Process::CLOCK_MONOTONIC
  ) + timeout

  loop do
    TCPSocket.new(host, port).close
    return
  rescue Errno::ECONNREFUSED, Errno::ECONNRESET
    now = Process.clock_gettime(
      Process::CLOCK_MONOTONIC
    )
    if now >= deadline
      raise "Server on #{host}:#{port} did not " \
            "start within #{timeout}s"
    end
    sleep 0.3
  end
end
