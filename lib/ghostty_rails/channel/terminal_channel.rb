require 'pty'

module GhosttyRails
  # Base terminal channel providing PTY-backed
  # shell sessions over ActionCable. Supports
  # local and SSH modes.
  #
  # Subclass this channel in your application and
  # override the hook methods to integrate with
  # your auth and SSH identity systems:
  #
  #   class TerminalChannel < GhosttyRails::TerminalChannel
  #     private
  #
  #     def authorize_terminal!(params)
  #       unless current_user.admin?
  #         raise GhosttyRails::UnauthorizedError
  #       end
  #     end
  #
  #     def resolve_ssh_params(params)
  #       host = Host.find(params[:host_id])
  #       {
  #         identity: host.ssh_key_path,
  #         user: host.ssh_user
  #       }
  #     end
  #   end
  class TerminalChannel < ActionCable::Channel::Base
    ALLOWED_AUTH_METHODS = %w[key password].freeze
    ALLOWED_MODES = %w[local ssh].freeze
    MAX_PORT = 65_535
    MIN_PORT = 1
    READER_JOIN_TIMEOUT = 5
    WAIT_POLL_INTERVAL = 0.2

    def receive(data)
      @mutex.synchronize do
        return unless @shell_write

        case data['type']
        when 'input'
          @shell_write.write(data['data'])
        when 'resize'
          resize_pty(data['cols'], data['rows'])
        end
      end
    rescue Errno::EIO, IOError => e
      log_warn("receive error: #{e.message}")
      stop_shell
    end

    def subscribed
      @mutex = Mutex.new
      @stopping = false
      @shell_pid = nil
      @shell_read = nil
      @shell_write = nil

      authorize_terminal!(params)

      unless valid_params?
        reject
        return
      end

      start_shell
    rescue GhosttyRails::UnauthorizedError
      reject
    end

    def unsubscribed
      stop_shell
    end

    private

    # Override in your subclass to enforce
    # authorization. Raise
    # GhosttyRails::UnauthorizedError to reject
    # the subscription.
    #
    # The default implementation permits all
    # authenticated connections (authentication
    # is handled at the ActionCable connection
    # level).
    def authorize_terminal!(_params)
      # no-op: override in your app's subclass
    end

    def close_shell_io
      [@shell_read, @shell_write].each do |io|
        next unless io

        io.close
      rescue IOError => e
        log_debug("IO close: #{e.message}")
      end
      @shell_read = nil
      @shell_write = nil
    end

    def config
      GhosttyRails.configuration
    end

    def local_mode?
      params[:mode].to_s == 'local'
    end

    def log_debug(msg)
      Rails.logger.debug(
        "GhosttyRails::TerminalChannel #{msg}"
      )
    end

    def log_warn(msg)
      Rails.logger.warn(
        "GhosttyRails::TerminalChannel #{msg}"
      )
    end

    def read_loop
      loop do
        break if @stopping

        readable = @mutex.synchronize { @shell_read }
        break unless readable

        begin
          data = readable.read_nonblock(4096)
          data.force_encoding('UTF-8')
          transmit({ type: 'output', data: data })
        rescue IO::WaitReadable
          IO.select([readable], nil, nil, 0.1)
          retry
        rescue Errno::EIO, IOError
          break
        end
      end

      reap_shell_process
      transmit({ type: 'exit' })
    end

    def reap_shell_process
      @mutex.synchronize do
        return unless @shell_pid

        pid = Process.waitpid(
          @shell_pid, Process::WNOHANG
        )
        @shell_pid = nil if pid
      end
    rescue Errno::ESRCH, Errno::ECHILD
      @shell_pid = nil
    end

    def resize_pty(cols, rows)
      return unless @shell_read && cols && rows

      @shell_read.winsize = [rows.to_i, cols.to_i]
    rescue Errno::EIO, IOError
      # PTY already closed, nothing to resize
    end

    # Override in your subclass to provide SSH
    # connection parameters from your domain
    # models. Return a hash with any of:
    #   identity: - path to SSH private key
    #   user:     - SSH username
    #
    # The default implementation returns an empty
    # hash, which means the channel will fall back
    # to the user/host/port from the subscription
    # params and no identity file.
    def resolve_ssh_params(_params)
      {}
    end

    def send_signal_to_group(signal, pid)
      Process.kill(signal, -pid)
    rescue Errno::ESRCH
      Process.kill(signal, pid)
    end

    def shell_command
      if local_mode?
        config.default_shell
      else
        ssh_command
      end
    end

    def ssh_command
      host = params[:ssh_host].to_s.strip
      port = ssh_port.to_s

      resolved = resolve_ssh_params(params)
      user = params[:ssh_user].to_s.strip
      user = resolved[:user] || 'root' if user.empty?

      cmd = [
        'ssh', '-tt',
        '-o', 'StrictHostKeyChecking=accept-new',
        '-o', 'ConnectTimeout=10',
        '-p', port
      ]

      identity = resolved[:identity]
      if identity
        cmd += [
          '-o', 'IdentitiesOnly=yes',
          '-i', identity
        ]
      end

      cmd << "#{user}@#{host}"

      if params[:ssh_auth_method] == 'password'
        cmd.insert(1, '-o')
        cmd.insert(
          2, 'PreferredAuthentications=password'
        )
      end

      cmd
    end

    def ssh_port
      port = params[:ssh_port].to_i
      if port < MIN_PORT || port > MAX_PORT
        22
      else
        port
      end
    end

    def start_shell
      @shell_read, @shell_write, @shell_pid =
        PTY.spawn(
          { 'TERM' => config.term_env },
          *shell_command
        )

      @reader_thread = Thread.new { read_loop }
    end

    def stop_shell
      @stopping = true

      @reader_thread&.join(READER_JOIN_TIMEOUT)
      @reader_thread = nil

      @mutex.synchronize do
        close_shell_io
        terminate_shell_process
      end
    end

    def terminate_shell_process
      return unless @shell_pid

      pid = @shell_pid

      send_signal_to_group('TERM', pid)
      wait = config.kill_escalation_wait
      if wait_for_exit(pid, wait)
        @shell_pid = nil
        return
      end

      log_warn(
        "SIGTERM ignored by #{pid}, " \
        'escalating to SIGKILL'
      )
      send_signal_to_group('KILL', pid)
      wait_for_exit(pid, wait)
      @shell_pid = nil
    rescue Errno::ESRCH, Errno::ECHILD => e
      log_debug(
        "process cleanup: #{e.message}"
      )
      @shell_pid = nil
    end

    def valid_params?
      mode = params[:mode].to_s
      return false unless ALLOWED_MODES.include?(mode)

      local_mode? || valid_ssh_params?
    end

    def valid_ssh_params?
      host = params[:ssh_host].to_s.strip
      return false if host.empty?
      return false if host.include?(' ')
      return false if host.include?(';')
      return false if host.include?('|')
      return false if host.include?('&')
      return false if host.include?('`')

      auth = params[:ssh_auth_method].to_s
      return false unless ALLOWED_AUTH_METHODS.include?(auth)

      true
    end

    def wait_for_exit(pid, timeout)
      deadline = Process.clock_gettime(
        Process::CLOCK_MONOTONIC
      ) + timeout

      loop do
        result = Process.waitpid(
          pid, Process::WNOHANG
        )
        return true if result

        now = Process.clock_gettime(
          Process::CLOCK_MONOTONIC
        )
        return false if now >= deadline

        sleep(WAIT_POLL_INTERVAL)
      end
    rescue Errno::ESRCH, Errno::ECHILD
      true
    end
  end
end
