require 'test_helper'

class TerminalChannelTest <
    ActionCable::Channel::TestCase
  tests GhosttyRails::TerminalChannel

  setup do
    stub_connection
    # Disable require_explicit_authorization for
    # existing tests that exercise the base channel
    # directly. Feature-specific tests re-enable it.
    GhosttyRails.configuration
                .require_explicit_authorization = false
  end

  teardown do
    GhosttyRails.configuration
                .require_explicit_authorization = true
    GhosttyRails.configuration.max_sessions = nil
    GhosttyRails.configuration.rate_limit = nil
    GhosttyRails.configuration.rate_limit_period = 60
    # Clear session registry between tests
    registry = GhosttyRails::TerminalChannel
               .instance_variable_get(:@sessions)
    registry.clear
    GhosttyRails::TerminalChannel
      .reset_rate_limits!
  end

  # -- mode validation -----------------------------

  test 'rejects when mode is missing' do
    subscribe(mode: nil)
    assert subscription.rejected?
  end

  test 'rejects when mode is invalid' do
    subscribe(mode: 'telnet')
    assert subscription.rejected?
  end

  # -- ssh param validation ------------------------

  test 'rejects ssh mode without host' do
    subscribe(
      mode: 'ssh',
      ssh_host: '',
      ssh_auth_method: 'key'
    )
    assert subscription.rejected?
  end

  test 'rejects ssh with semicolon in host' do
    subscribe(
      mode: 'ssh',
      ssh_host: 'host;rm -rf /',
      ssh_auth_method: 'key'
    )
    assert subscription.rejected?
  end

  test 'rejects ssh with pipe in host' do
    subscribe(
      mode: 'ssh',
      ssh_host: 'host|cat /etc/passwd',
      ssh_auth_method: 'key'
    )
    assert subscription.rejected?
  end

  test 'rejects ssh with ampersand in host' do
    subscribe(
      mode: 'ssh',
      ssh_host: 'host&bg',
      ssh_auth_method: 'key'
    )
    assert subscription.rejected?
  end

  test 'rejects ssh with backtick in host' do
    subscribe(
      mode: 'ssh',
      ssh_host: 'host`whoami`',
      ssh_auth_method: 'key'
    )
    assert subscription.rejected?
  end

  test 'rejects ssh with space in host' do
    subscribe(
      mode: 'ssh',
      ssh_host: 'host name',
      ssh_auth_method: 'key'
    )
    assert subscription.rejected?
  end

  test 'rejects ssh with invalid auth method' do
    subscribe(
      mode: 'ssh',
      ssh_host: '10.0.0.1',
      ssh_auth_method: 'certificate'
    )
    assert subscription.rejected?
  end

  # -- ssh_command construction --------------------

  test 'ssh_command defaults user to root' do
    subscribe(
      mode: 'ssh',
      ssh_host: '10.0.0.1',
      ssh_port: '22',
      ssh_user: '',
      ssh_auth_method: 'key'
    )
    cmd = subscription.send(:ssh_command)
    assert_includes cmd, 'root@10.0.0.1'
  end

  test 'ssh_command uses specified port' do
    subscribe(
      mode: 'ssh',
      ssh_host: '10.0.0.1',
      ssh_port: '2222',
      ssh_user: 'root',
      ssh_auth_method: 'key'
    )
    cmd = subscription.send(:ssh_command)
    port_idx = cmd.index('-p')
    assert_not_nil port_idx
    assert_equal '2222', cmd[port_idx + 1]
  end

  test 'ssh_command adds password auth pref' do
    subscribe(
      mode: 'ssh',
      ssh_host: '10.0.0.1',
      ssh_port: '22',
      ssh_user: 'root',
      ssh_auth_method: 'password'
    )
    cmd = subscription.send(:ssh_command)
    assert_includes cmd,
                    'PreferredAuthentications=password'
  end

  test 'ssh_command omits IdentitiesOnly by ' \
    'default' do
    subscribe(
      mode: 'ssh',
      ssh_host: '10.0.0.1',
      ssh_port: '22',
      ssh_user: 'root',
      ssh_auth_method: 'key'
    )
    cmd = subscription.send(:ssh_command)
    refute_includes cmd, 'IdentitiesOnly=yes'
  end

  # -- ssh_port ------------------------------------

  test 'ssh_port defaults to 22 for out of ' \
    'range' do
    subscribe(
      mode: 'ssh',
      ssh_host: '10.0.0.1',
      ssh_port: '99999',
      ssh_user: 'root',
      ssh_auth_method: 'key'
    )
    port = subscription.send(:ssh_port)
    assert_equal 22, port
  end

  test 'ssh_port defaults to 22 for zero' do
    subscribe(
      mode: 'ssh',
      ssh_host: '10.0.0.1',
      ssh_port: '0',
      ssh_user: 'root',
      ssh_auth_method: 'key'
    )
    port = subscription.send(:ssh_port)
    assert_equal 22, port
  end

  test 'ssh_port defaults to 22 for negative' do
    subscribe(
      mode: 'ssh',
      ssh_host: '10.0.0.1',
      ssh_port: '-1',
      ssh_user: 'root',
      ssh_auth_method: 'key'
    )
    port = subscription.send(:ssh_port)
    assert_equal 22, port
  end

  # -- authorize_terminal! hook --------------------

  test 'rejects when authorize_terminal! ' \
    'raises UnauthorizedError' do
    denied_channel = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      def authorize_terminal!(_params)
        raise GhosttyRails::UnauthorizedError
      end
    end

    self.class.tests denied_channel
    subscribe(mode: 'local')
    assert subscription.rejected?
  ensure
    self.class.tests(
      GhosttyRails::TerminalChannel
    )
  end

  # -- default-secure authorization ----------------

  test 'default auth permits in test env with ' \
    'require_explicit_authorization' do
    GhosttyRails.configuration
                .require_explicit_authorization = true

    # In test env, the base authorize_terminal!
    # logs a warning but does NOT reject.
    subscribe(mode: 'local')
    refute subscription.rejected?
  end

  test 'default auth rejects in production env' do
    GhosttyRails.configuration
                .require_explicit_authorization = true

    # Temporarily stub Rails.env as production.
    # Rails 8 stores env in @_env as an
    # EnvironmentInquirer, not @env.
    old_env = Rails.instance_variable_get(:@_env)
    Rails.instance_variable_set(
      :@_env,
      ActiveSupport::EnvironmentInquirer
        .new('production')
    )

    subscribe(mode: 'local')
    assert subscription.rejected?
  ensure
    Rails.instance_variable_set(:@_env, old_env)
  end

  test 'default auth permits when config ' \
    'disabled' do
    GhosttyRails.configuration
                .require_explicit_authorization = false

    # Even in production, if the config is false
    # the base method is a no-op.
    old_env = Rails.instance_variable_get(:@_env)
    Rails.instance_variable_set(
      :@_env,
      ActiveSupport::EnvironmentInquirer
        .new('production')
    )

    subscribe(mode: 'local')
    refute subscription.rejected?
  ensure
    Rails.instance_variable_set(:@_env, old_env)
  end

  test 'overridden auth bypasses default-secure ' \
    'behavior' do
    GhosttyRails.configuration
                .require_explicit_authorization = true

    # A subclass that overrides authorize_terminal!
    # should work even in production.
    permissive = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      def authorize_terminal!(_params)
        # explicitly permit
      end
    end

    old_env = Rails.instance_variable_get(:@_env)
    Rails.instance_variable_set(
      :@_env,
      ActiveSupport::EnvironmentInquirer
        .new('production')
    )

    self.class.tests permissive
    subscribe(mode: 'local')
    refute subscription.rejected?
  ensure
    Rails.instance_variable_set(:@_env, old_env)
    self.class.tests(
      GhosttyRails::TerminalChannel
    )
  end

  # -- resolve_ssh_params hook ---------------------

  test 'resolve_ssh_params returns empty hash ' \
    'by default' do
    subscribe(
      mode: 'ssh',
      ssh_host: '10.0.0.1',
      ssh_auth_method: 'key'
    )
    result = subscription.send(
      :resolve_ssh_params, {}
    )
    assert_equal({}, result)
  end

  test 'resolve_ssh_params called before ' \
    'authorize_terminal!' do
    # Verify that @resolved_ssh is populated
    # before authorize_terminal! runs, by using
    # a subclass that checks it during auth.
    call_order = []
    checking_channel = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      define_method(:resolve_ssh_params) do |_p|
        call_order << :resolve
        { user: 'deploy' }
      end

      define_method(:authorize_terminal!) do |_p|
        call_order << :authorize
        resolved = instance_variable_get(
          :@resolved_ssh
        )
        return if resolved[:user] == 'deploy'

        raise GhosttyRails::UnauthorizedError
      end
    end

    self.class.tests checking_channel
    subscribe(
      mode: 'ssh',
      ssh_host: '10.0.0.1',
      ssh_auth_method: 'key'
    )

    refute subscription.rejected?
    assert_equal %i[resolve authorize], call_order
  ensure
    self.class.tests(
      GhosttyRails::TerminalChannel
    )
  end

  test 'ssh_command uses pre-resolved params ' \
    'not a second call' do
    call_count = 0
    counting_channel = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      define_method(:resolve_ssh_params) do |_p|
        call_count += 1
        { user: 'deploy' }
      end

      def authorize_terminal!(_params)
        # permit
      end
    end

    self.class.tests counting_channel
    subscribe(
      mode: 'ssh',
      ssh_host: '10.0.0.1',
      ssh_port: '22',
      ssh_user: '',
      ssh_auth_method: 'key'
    )

    cmd = subscription.send(:ssh_command)
    assert_includes cmd, 'deploy@10.0.0.1'
    # resolve_ssh_params called once in subscribed,
    # ssh_command uses @resolved_ssh
    assert_equal 1, call_count
  ensure
    self.class.tests(
      GhosttyRails::TerminalChannel
    )
  end

  # -- session registry ----------------------------

  test 'active_sessions returns empty when no ' \
    'sessions' do
    sessions = GhosttyRails::TerminalChannel
               .active_sessions
    assert_equal({}, sessions)
  end

  test 'session_count returns zero initially' do
    count = GhosttyRails::TerminalChannel
            .session_count
    assert_equal 0, count
  end

  # -- max_sessions enforcement --------------------

  test 'rejects when max_sessions reached' do
    GhosttyRails.configuration.max_sessions = 0
    subscribe(mode: 'local')
    assert subscription.rejected?
  end

  test 'permits when under max_sessions' do
    GhosttyRails.configuration.max_sessions = 10
    subscribe(mode: 'local')
    refute subscription.rejected?
  end

  test 'permits when max_sessions is nil' do
    GhosttyRails.configuration.max_sessions = nil
    subscribe(mode: 'local')
    refute subscription.rejected?
  end

  test 'max_sessions rejects at exact boundary' do
    GhosttyRails.configuration.max_sessions = 2

    subscribe(mode: 'local')
    refute subscription.rejected?

    subscribe(mode: 'local')
    refute subscription.rejected?

    # Third session hits the cap (count == max)
    subscribe(mode: 'local')
    assert subscription.rejected?
  end

  test 'max_sessions permits after unsubscribe ' \
    'frees a slot' do
    GhosttyRails.configuration.max_sessions = 1

    subscribe(mode: 'local')
    refute subscription.rejected?
    first = subscription

    # Second should be rejected (at cap)
    subscribe(mode: 'local')
    assert subscription.rejected?

    # Disconnect the first session
    first.unsubscribe_from_channel

    # Now a new session should be permitted
    subscribe(mode: 'local')
    refute subscription.rejected?,
           'should permit after a session disconnects'
  end

  # -- on_input hook -------------------------------

  test 'on_input called before PTY write' do
    inputs = []
    hooking_channel = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      define_method(:on_input) do |data, _params|
        inputs << data
      end

      def authorize_terminal!(_params)
        # permit
      end
    end

    self.class.tests hooking_channel
    subscribe(mode: 'local')
    refute subscription.rejected?

    # The shell_write is a real PTY; we just want
    # to verify on_input is invoked.
    subscription.receive(
      'type' => 'input', 'data' => 'ls'
    )
    assert_equal ['ls'], inputs
  ensure
    self.class.tests(
      GhosttyRails::TerminalChannel
    )
  end

  # -- on_output hook ------------------------------

  test 'on_output is defined as a no-op' do
    subscribe(mode: 'local')
    # Should not raise; returns nil (no-op)
    result = subscription.send(
      :on_output, 'data', {}
    )
    assert_nil result
  end

  test 'on_output called with PTY data' do
    outputs = []
    mutex = Mutex.new
    hooking_channel = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      define_method(:on_output) do |data, _params|
        mutex.synchronize { outputs << data }
      end

      def authorize_terminal!(_params)
        # permit
      end
    end

    self.class.tests hooking_channel
    subscribe(mode: 'local')
    refute subscription.rejected?

    # Send input that produces output. The echo
    # command writes to stdout which the read_loop
    # thread picks up and passes to on_output.
    subscription.receive(
      'type' => 'input',
      'data' => "echo ghostty_hook_test\n"
    )

    # Wait for the read thread to deliver output.
    # PTY echo is fast but asynchronous; poll with
    # a generous timeout to avoid flaky failures.
    deadline = Time.now + 5
    loop do
      found = mutex.synchronize do
        outputs.any? { |o| o.include?('ghostty_hook_test') }
      end
      break if found
      break if Time.now > deadline

      sleep 0.05
    end

    captured = mutex.synchronize { outputs.join }
    assert_includes captured, 'ghostty_hook_test',
                    'on_output should receive PTY data ' \
                    'containing the echoed string'
  ensure
    self.class.tests(
      GhosttyRails::TerminalChannel
    )
  end

  # -- configuration -------------------------------

  test 'configuration defaults are sane' do
    config = GhosttyRails::Configuration.new
    assert_equal ['bash', '--login'],
                 config.default_shell
    assert_equal 'xterm-256color',
                 config.term_env
    assert_equal 3, config.kill_escalation_wait
    assert config.require_explicit_authorization
    assert_nil config.max_sessions
  end

  test 'configure block modifies settings' do
    GhosttyRails.configure do |c|
      c.default_shell = ['/bin/zsh']
    end
    assert_equal ['/bin/zsh'],
                 GhosttyRails.configuration
                             .default_shell
  ensure
    GhosttyRails.configuration.default_shell =
      ['bash', '--login']
  end

  test 'configure sets max_sessions' do
    GhosttyRails.configure do |c|
      c.max_sessions = 5
    end
    assert_equal 5,
                 GhosttyRails.configuration
                             .max_sessions
  ensure
    GhosttyRails.configuration.max_sessions = nil
  end

  test 'configure sets ' \
    'require_explicit_authorization' do
    GhosttyRails.configure do |c|
      c.require_explicit_authorization = false
    end
    refute GhosttyRails.configuration
                       .require_explicit_authorization
  ensure
    GhosttyRails.configuration
                .require_explicit_authorization = true
  end

  # -- rate limit config defaults --------------------

  test 'rate_limit defaults to nil' do
    config = GhosttyRails::Configuration.new
    assert_nil config.rate_limit
  end

  test 'rate_limit_period defaults to 60' do
    config = GhosttyRails::Configuration.new
    assert_equal 60, config.rate_limit_period
  end

  test 'configure sets rate_limit' do
    GhosttyRails.configure do |c|
      c.rate_limit = 10
    end
    assert_equal 10,
                 GhosttyRails.configuration
                             .rate_limit
  ensure
    GhosttyRails.configuration.rate_limit = nil
  end

  test 'configure sets rate_limit_period' do
    GhosttyRails.configure do |c|
      c.rate_limit_period = 120
    end
    assert_equal 120,
                 GhosttyRails.configuration
                             .rate_limit_period
  ensure
    GhosttyRails.configuration
                .rate_limit_period = 60
  end

  # -- rate limiting enforcement ---------------------

  test 'permits when rate_limit is nil' do
    GhosttyRails.configuration.rate_limit = nil
    subscribe(mode: 'local')
    refute subscription.rejected?
  end

  test 'permits when under rate_limit' do
    GhosttyRails.configuration.rate_limit = 5
    subscribe(mode: 'local')
    refute subscription.rejected?
  end

  test 'rejects when rate_limit exceeded' do
    GhosttyRails.configuration.rate_limit = 2

    # First two subscriptions should succeed
    subscribe(mode: 'local')
    refute subscription.rejected?

    subscribe(mode: 'local')
    refute subscription.rejected?

    # Third should be rejected
    subscribe(mode: 'local')
    assert subscription.rejected?
  end

  test 'reset_rate_limits! clears tracking' do
    GhosttyRails.configuration.rate_limit = 1

    subscribe(mode: 'local')
    refute subscription.rejected?

    # Should be rejected now
    subscribe(mode: 'local')
    assert subscription.rejected?

    # Reset and try again
    GhosttyRails::TerminalChannel
      .reset_rate_limits!

    subscribe(mode: 'local')
    refute subscription.rejected?
  end

  test 'rate_limit_key defaults to ' \
    'connection_identifier' do
    subscribe(mode: 'local')
    key = subscription.send(:rate_limit_key)
    expected = subscription.send(
      :connection_identifier
    )
    assert_equal expected, key
  end

  test 'rate limit sliding window expires old events' do
    GhosttyRails.configuration.rate_limit = 1
    GhosttyRails.configuration.rate_limit_period = 1

    subscribe(mode: 'local')
    refute subscription.rejected?

    # Second subscribe should be rejected (limit=1)
    subscribe(mode: 'local')
    assert subscription.rejected?

    # Manually backdate the recorded timestamps so
    # they fall outside the 1-second window. This
    # avoids sleeping and keeps the test fast.
    klass = GhosttyRails::TerminalChannel
    mutex = klass.instance_variable_get(
      :@rate_limits_mutex
    )
    limits = klass.instance_variable_get(
      :@rate_limits
    )
    old_time = Process.clock_gettime(
      Process::CLOCK_MONOTONIC
    ) - 2.0

    mutex.synchronize do
      limits.each_key do |k|
        limits[k] = [old_time]
      end
    end

    # Now should be permitted again -- the old
    # event is outside the sliding window.
    subscribe(mode: 'local')
    refute subscription.rejected?,
           'should permit after rate limit window expires'
  end

  test 'custom rate_limit_key groups separately' do
    GhosttyRails.configuration.rate_limit = 1

    # Channel A uses "group_a" as key
    channel_a = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      def authorize_terminal!(_params); end

      def rate_limit_key
        'group_a'
      end
    end

    # Channel B uses "group_b" as key
    channel_b = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      def authorize_terminal!(_params); end

      def rate_limit_key
        'group_b'
      end
    end

    # Subscribe with channel_a -- should pass
    self.class.tests channel_a
    subscribe(mode: 'local')
    refute subscription.rejected?

    # Subscribe with channel_b -- should also pass
    # (different rate limit key)
    self.class.tests channel_b
    subscribe(mode: 'local')
    refute subscription.rejected?

    # Subscribe with channel_a again -- should fail
    # (group_a already at limit)
    self.class.tests channel_a
    subscribe(mode: 'local')
    assert subscription.rejected?
  ensure
    self.class.tests(
      GhosttyRails::TerminalChannel
    )
  end

  # -- session lifecycle hooks -----------------------

  test 'session_id is a public accessor' do
    subscribe(mode: 'local')
    refute subscription.rejected?
    assert_kind_of String, subscription.session_id
    # UUIDs are 36 chars: 8-4-4-4-12
    assert_match(
      /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/,
      subscription.session_id
    )
  end

  test 'on_session_start called after subscribe' do
    started = []
    hooking_channel = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      define_method(:on_session_start) do
        started << session_id
      end

      def authorize_terminal!(_params); end
    end

    self.class.tests hooking_channel
    subscribe(mode: 'local')
    refute subscription.rejected?

    assert_equal 1, started.length
    assert_equal subscription.session_id,
                 started.first
  ensure
    self.class.tests(
      GhosttyRails::TerminalChannel
    )
  end

  test 'on_session_end called on unsubscribe' do
    ended = []
    hooking_channel = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      define_method(:on_session_end) do
        ended << session_id
      end

      def authorize_terminal!(_params); end
    end

    self.class.tests hooking_channel
    subscribe(mode: 'local')
    refute subscription.rejected?
    sid = subscription.session_id

    subscription.unsubscribe_from_channel
    assert_equal 1, ended.length
    assert_equal sid, ended.first
  ensure
    self.class.tests(
      GhosttyRails::TerminalChannel
    )
  end

  test 'on_session_start has access to params' do
    captured_mode = nil
    hooking_channel = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      define_method(:on_session_start) do
        captured_mode = params[:mode]
      end

      def authorize_terminal!(_params); end
    end

    self.class.tests hooking_channel
    subscribe(mode: 'local')
    refute subscription.rejected?
    assert_equal 'local', captured_mode
  ensure
    self.class.tests(
      GhosttyRails::TerminalChannel
    )
  end

  # -- connection_identifier -------------------------

  test 'connection_identifier defaults to ' \
    'connection.connection_identifier' do
    subscribe(mode: 'local')
    refute subscription.rejected?
    expected = subscription.connection
                           .connection_identifier
    actual = subscription.send(:connection_identifier)
    assert_equal expected, actual
  end

  test 'overridden connection_identifier is used ' \
    'in registry' do
    custom_channel = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      def authorize_terminal!(_params); end

      def connection_identifier
        'user_42'
      end
    end

    self.class.tests custom_channel
    subscribe(mode: 'local')
    refute subscription.rejected?

    session = custom_channel.find_session(
      subscription.session_id
    )
    assert_equal 'user_42',
                 session[:connection_identifier]
  ensure
    # Clean up the subclass registry
    registry = custom_channel
               .instance_variable_get(:@sessions)
    registry&.clear
    self.class.tests(
      GhosttyRails::TerminalChannel
    )
  end

  # -- find_session ----------------------------------

  test 'find_session returns nil for unknown id' do
    result = GhosttyRails::TerminalChannel
             .find_session('nonexistent')
    assert_nil result
  end

  test 'find_session returns session after ' \
    'subscribe' do
    subscribe(mode: 'local')
    refute subscription.rejected?

    session = GhosttyRails::TerminalChannel
              .find_session(subscription.session_id)
    assert_not_nil session
    assert_equal subscription.session_id,
                 session[:session_id]
    assert_equal 'local', session[:mode]
    assert_kind_of Time, session[:started_at]
    assert_not_nil session[:pid]
  end

  test 'find_session returns dup not reference' do
    subscribe(mode: 'local')
    refute subscription.rejected?

    s1 = GhosttyRails::TerminalChannel
         .find_session(subscription.session_id)
    s2 = GhosttyRails::TerminalChannel
         .find_session(subscription.session_id)

    refute_same s1, s2
  end

  # -- sessions_for ----------------------------------

  test 'sessions_for returns empty for unknown ' \
    'identifier' do
    result = GhosttyRails::TerminalChannel
             .sessions_for('nobody')
    assert_equal({}, result)
  end

  test 'sessions_for returns matching sessions' do
    custom_channel = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      def authorize_terminal!(_params); end

      def connection_identifier
        'user_99'
      end
    end

    self.class.tests custom_channel
    subscribe(mode: 'local')
    refute subscription.rejected?

    sessions = custom_channel.sessions_for('user_99')
    assert_equal 1, sessions.size
    assert_equal 'user_99',
                 sessions.values
                         .first[:connection_identifier]
  ensure
    registry = custom_channel
               .instance_variable_get(:@sessions)
    registry&.clear
    self.class.tests(
      GhosttyRails::TerminalChannel
    )
  end

  # -- session_count_for -----------------------------

  test 'session_count_for returns zero for ' \
    'unknown identifier' do
    count = GhosttyRails::TerminalChannel
            .session_count_for('nobody')
    assert_equal 0, count
  end

  test 'session_count_for counts matching ' \
    'sessions' do
    custom_channel = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      def authorize_terminal!(_params); end

      def connection_identifier
        'user_77'
      end
    end

    self.class.tests custom_channel
    subscribe(mode: 'local')
    refute subscription.rejected?

    count = custom_channel
            .session_count_for('user_77')
    assert_equal 1, count

    subscribe(mode: 'local')
    refute subscription.rejected?

    count = custom_channel
            .session_count_for('user_77')
    assert_equal 2, count
  ensure
    registry = custom_channel
               .instance_variable_get(:@sessions)
    registry&.clear
    self.class.tests(
      GhosttyRails::TerminalChannel
    )
  end

  # -- force_disconnect_all --------------------------

  test 'force_disconnect_all returns zero when ' \
    'no sessions' do
    count = GhosttyRails::TerminalChannel
            .force_disconnect_all
    assert_equal 0, count
  end

  test 'force_disconnect_all kills all sessions' do
    subscribe(mode: 'local')
    refute subscription.rejected?

    subscribe(mode: 'local')
    refute subscription.rejected?

    assert_operator(
      GhosttyRails::TerminalChannel.session_count,
      :>=, 2
    )

    count = GhosttyRails::TerminalChannel
            .force_disconnect_all
    assert_operator count, :>=, 2
  end

  # -- force_disconnect ------------------------------

  test 'force_disconnect returns false for ' \
    'unknown session' do
    result = GhosttyRails::TerminalChannel
             .force_disconnect('nonexistent')
    assert_equal false, result
  end

  test 'force_disconnect kills a specific ' \
    'session' do
    subscribe(mode: 'local')
    refute subscription.rejected?
    sid = subscription.session_id

    result = GhosttyRails::TerminalChannel
             .force_disconnect(sid)
    assert_equal true, result
  end

  # -- per-user session cap pattern ------------------

  test 'per-user session cap via ' \
    'authorize_terminal!' do
    capped_channel = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      def connection_identifier
        'capped_user'
      end

      def authorize_terminal!(_params)
        if self.class.session_count_for(
          connection_identifier
        ) >= 1
          raise GhosttyRails::UnauthorizedError,
                'too many terminals'
        end
      end
    end

    self.class.tests capped_channel

    # First session should succeed
    subscribe(mode: 'local')
    refute subscription.rejected?

    # Second session should be rejected (cap of 1)
    subscribe(mode: 'local')
    assert subscription.rejected?
  ensure
    registry = capped_channel
               .instance_variable_get(:@sessions)
    registry&.clear
    self.class.tests(
      GhosttyRails::TerminalChannel
    )
  end

  # -- RateLimitedError class existence --------------

  test 'RateLimitedError is defined' do
    assert defined?(GhosttyRails::RateLimitedError)
    assert_operator GhosttyRails::RateLimitedError,
                    :<, StandardError
  end

  # -- SSH host allowlist (Commit 1) -----------------

  test 'rejects ssh host with dollar-paren ' \
    'injection' do
    subscribe(
      mode: 'ssh',
      ssh_host: '$(whoami)',
      ssh_auth_method: 'key'
    )
    assert subscription.rejected?
  end

  test 'rejects ssh host with newline' do
    subscribe(
      mode: 'ssh',
      ssh_host: "host\nid",
      ssh_auth_method: 'key'
    )
    assert subscription.rejected?
  end

  test 'rejects ssh host with curly braces' do
    subscribe(
      mode: 'ssh',
      ssh_host: '{bad}',
      ssh_auth_method: 'key'
    )
    assert subscription.rejected?
  end

  test 'accepts valid hostname' do
    subscribe(
      mode: 'ssh',
      ssh_host: 'web-01.example.com',
      ssh_auth_method: 'key'
    )
    refute subscription.rejected?
  end

  test 'accepts IPv4 address' do
    subscribe(
      mode: 'ssh',
      ssh_host: '192.168.1.1',
      ssh_auth_method: 'key'
    )
    refute subscription.rejected?
  end

  test 'accepts IPv6 address' do
    subscribe(
      mode: 'ssh',
      ssh_host: '::1',
      ssh_auth_method: 'key'
    )
    refute subscription.rejected?
  end

  # -- SSH user validation (Commit 1) ----------------

  test 'rejects ssh user with semicolon' do
    subscribe(
      mode: 'ssh',
      ssh_host: '10.0.0.1',
      ssh_user: 'root;rm -rf /',
      ssh_auth_method: 'key'
    )
    assert subscription.rejected?
  end

  test 'rejects ssh user with backtick' do
    subscribe(
      mode: 'ssh',
      ssh_host: '10.0.0.1',
      ssh_user: '`whoami`',
      ssh_auth_method: 'key'
    )
    assert subscription.rejected?
  end

  test 'rejects ssh user with space' do
    subscribe(
      mode: 'ssh',
      ssh_host: '10.0.0.1',
      ssh_user: 'bad user',
      ssh_auth_method: 'key'
    )
    assert subscription.rejected?
  end

  test 'accepts valid ssh user' do
    subscribe(
      mode: 'ssh',
      ssh_host: '10.0.0.1',
      ssh_user: 'deploy_v2',
      ssh_auth_method: 'key'
    )
    refute subscription.rejected?
  end

  test 'accepts empty ssh user (defaults later)' do
    subscribe(
      mode: 'ssh',
      ssh_host: '10.0.0.1',
      ssh_user: '',
      ssh_auth_method: 'key'
    )
    refute subscription.rejected?
  end

  # -- effective_ssh_user (Commit 1) -----------------

  test 'effective_ssh_user prefers param over ' \
    'resolved' do
    resolving = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      def authorize_terminal!(_params); end

      def resolve_ssh_params(_params)
        { user: 'resolved_user' }
      end
    end

    self.class.tests resolving
    subscribe(
      mode: 'ssh',
      ssh_host: '10.0.0.1',
      ssh_user: 'param_user',
      ssh_auth_method: 'key'
    )
    refute subscription.rejected?
    assert_equal 'param_user',
                 subscription.send(
                   :effective_ssh_user
                 )
  ensure
    resolving.instance_variable_get(:@sessions)
             &.clear
    self.class.tests(
      GhosttyRails::TerminalChannel
    )
  end

  test 'effective_ssh_user falls back to ' \
    'resolved' do
    resolving = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      def authorize_terminal!(_params); end

      def resolve_ssh_params(_params)
        { user: 'resolved_user' }
      end
    end

    self.class.tests resolving
    subscribe(
      mode: 'ssh',
      ssh_host: '10.0.0.1',
      ssh_user: '',
      ssh_auth_method: 'key'
    )
    refute subscription.rejected?
    assert_equal 'resolved_user',
                 subscription.send(
                   :effective_ssh_user
                 )
  ensure
    resolving.instance_variable_get(:@sessions)
             &.clear
    self.class.tests(
      GhosttyRails::TerminalChannel
    )
  end

  # -- receive edge cases (Commit 2) -----------------

  test 'receive with resize does not raise' do
    subscribe(mode: 'local')
    refute subscription.rejected?
    # Should not raise
    subscription.receive(
      'type' => 'resize',
      'cols' => 120,
      'rows' => 40
    )
  end

  test 'receive with unknown type does not ' \
    'raise' do
    subscribe(mode: 'local')
    refute subscription.rejected?
    # Unknown types are silently ignored
    subscription.receive(
      'type' => 'bogus',
      'data' => 'whatever'
    )
  end

  test 'receive with nil data does not crash' do
    subscribe(mode: 'local')
    refute subscription.rejected?
    # data['data'] is nil -- should not raise
    subscription.receive(
      'type' => 'input',
      'data' => nil
    )
  end

  # -- on_session_end guard (Commit 2) ---------------

  test 'on_session_end not called for rejected ' \
    'subscription' do
    ended = []
    guarded = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      define_method(:on_session_end) do
        ended << session_id
      end

      # Reject every subscription
      def authorize_terminal!(_params)
        raise GhosttyRails::UnauthorizedError
      end
    end

    self.class.tests guarded
    subscribe(mode: 'local')
    assert subscription.rejected?

    subscription.unsubscribe_from_channel
    assert_empty ended,
                 'on_session_end should not fire ' \
                 'for a rejected subscription'
  ensure
    self.class.tests(
      GhosttyRails::TerminalChannel
    )
  end

  # -- on_session_start not called for rejected ------

  test 'on_session_start not called for rejected ' \
    'subscription' do
    started = []
    guarded = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      define_method(:on_session_start) do
        started << session_id
      end

      def authorize_terminal!(_params)
        raise GhosttyRails::UnauthorizedError
      end
    end

    self.class.tests guarded
    subscribe(mode: 'local')
    assert subscription.rejected?
    assert_empty started,
                 'on_session_start should not fire ' \
                 'for a rejected subscription'
  ensure
    self.class.tests(
      GhosttyRails::TerminalChannel
    )
  end
end
