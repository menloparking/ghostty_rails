require 'test_helper'

class TerminalChannelTest <
    ActionCable::Channel::TestCase
  tests GhosttyRails::TerminalChannel

  setup do
    stub_connection
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
    # Create a subclass that always denies
    denied_channel = Class.new(
      GhosttyRails::TerminalChannel
    ) do
      def authorize_terminal!(_params)
        raise GhosttyRails::UnauthorizedError
      end
    end

    # Temporarily swap the tested channel
    self.class.tests denied_channel
    subscribe(mode: 'local')
    assert subscription.rejected?
  ensure
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

  # -- configuration -------------------------------

  test 'configuration defaults are sane' do
    config = GhosttyRails.configuration
    assert_equal ['bash', '--login'],
                 config.default_shell
    assert_equal 'xterm-256color',
                 config.term_env
    assert_equal 3, config.kill_escalation_wait
    assert_equal 10_000, config.scrollback
  end

  test 'configure block modifies settings' do
    GhosttyRails.configure do |c|
      c.default_shell = ['/bin/zsh']
    end
    assert_equal ['/bin/zsh'],
                 GhosttyRails.configuration.default_shell
  ensure
    GhosttyRails.configuration.default_shell =
      ['bash', '--login']
  end
end
