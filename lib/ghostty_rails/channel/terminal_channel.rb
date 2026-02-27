require 'pty'
require 'securerandom'

module GhosttyRails
  # Base terminal channel providing PTY-backed
  # shell sessions over ActionCable. Supports
  # local and SSH modes.
  #
  # Subclass this channel in your application and
  # override the hook methods to integrate with
  # your auth and SSH identity systems:
  #
  #   class TerminalChannel <
  #       GhosttyRails::TerminalChannel
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
  #
  #     # Optional hooks for audit logging:
  #     def on_input(data, params)
  #       AuditLog.record(:input, data, params)
  #     end
  #
  #     def on_output(data, params)
  #       AuditLog.record(:output, data, params)
  #     end
  #   end
  class TerminalChannel < ActionCable::Channel::Base
    ALLOWED_AUTH_METHODS = %w[key password].freeze
    ALLOWED_MODES = %w[local ssh].freeze
    MAX_PORT = 65_535
    MIN_PORT = 1
    READER_JOIN_TIMEOUT = 5
    WAIT_POLL_INTERVAL = 0.2

    # -- session registry ----------------------------
    # Thread-safe registry of all active terminal
    # sessions across the process. Keyed by a
    # unique session id.

    @sessions_mutex = Mutex.new
    @sessions = {}
    @rate_limits_mutex = Mutex.new
    @rate_limits = {}

    class << self
      # Ensure subclasses get their own session
      # registry so they do not share (or lack)
      # the base class's instance variables.
      def inherited(subclass)
        super
        subclass.instance_variable_set(
          :@sessions_mutex, Mutex.new
        )
        subclass.instance_variable_set(
          :@sessions, {}
        )
        subclass.instance_variable_set(
          :@rate_limits_mutex, Mutex.new
        )
        subclass.instance_variable_set(
          :@rate_limits, {}
        )
      end

      # Returns a frozen snapshot of all active
      # sessions. Each entry is a hash with:
      #   :session_id, :channel, :started_at,
      #   :mode, :pid, :connection_identifier,
      #   :params
      def active_sessions
        @sessions_mutex.synchronize do
          @sessions.transform_values(&:dup).freeze
        end
      end

      # Look up a single session by id. Returns
      # a dup of the session hash or nil.
      def find_session(session_id)
        @sessions_mutex.synchronize do
          entry = @sessions[session_id]
          entry&.dup
        end
      end

      # Forcibly disconnect a session by its id.
      # Returns true if found and stopped, false
      # otherwise.
      def force_disconnect(session_id)
        channel = @sessions_mutex.synchronize do
          entry = @sessions[session_id]
          entry&.[](:channel)
        end
        return false unless channel

        channel.stop_stream_from(session_id)
        channel.unsubscribe_from_channel
        true
      end

      # Forcibly disconnect all active sessions.
      # Returns the number of sessions stopped.
      def force_disconnect_all
        ids = @sessions_mutex.synchronize do
          @sessions.keys.dup
        end

        ids.count { |id| force_disconnect(id) }
      end

      # Returns the current session count.
      def session_count
        @sessions_mutex.synchronize do
          @sessions.size
        end
      end

      # Returns active sessions whose
      # :connection_identifier matches the given
      # key. Useful for per-user session caps.
      #
      #   TerminalChannel.sessions_for("user_42")
      def sessions_for(identifier)
        @sessions_mutex.synchronize do
          @sessions.select do |_, v|
            v[:connection_identifier] == identifier
          end.transform_values(&:dup).freeze
        end
      end

      # Returns the count of active sessions for
      # a given connection identifier.
      def session_count_for(identifier)
        @sessions_mutex.synchronize do
          @sessions.count do |_, v|
            v[:connection_identifier] == identifier
          end
        end
      end

      # Resets rate limit tracking. Primarily
      # useful in tests.
      def reset_rate_limits!
        @rate_limits_mutex.synchronize do
          @rate_limits.clear
        end
      end

      private

      def deregister_session(session_id)
        @sessions_mutex.synchronize do
          @sessions.delete(session_id)
        end
      end

      def register_session(session_id, info)
        @sessions_mutex.synchronize do
          @sessions[session_id] = info
        end
      end

      def record_rate_limit_event(key)
        now = monotonic_now
        @rate_limits_mutex.synchronize do
          @rate_limits[key] ||= []
          @rate_limits[key] << now
        end
      end

      def rate_limit_count(key, window)
        cutoff = monotonic_now - window
        @rate_limits_mutex.synchronize do
          timestamps = @rate_limits[key]
          return 0 unless timestamps

          # Prune old entries
          timestamps.reject! { |t| t < cutoff }
          timestamps.size
        end
      end

      def monotonic_now
        Process.clock_gettime(
          Process::CLOCK_MONOTONIC
        )
      end
    end

    # ------------------------------------------------

    # Public accessor so subclasses and callbacks
    # can reference the session id for logging,
    # recording, etc.
    attr_reader :session_id

    def receive(data)
      @mutex.synchronize do
        return unless @shell_write

        case data['type']
        when 'input'
          input = data['data']
          on_input(input, params)
          @shell_write.write(input)
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
      @session_id = SecureRandom.uuid

      # Resolve SSH params before authorization so
      # authorize_terminal! sees the final effective
      # parameters (identity, user) rather than raw
      # subscription params. This prevents an
      # authorization bypass where resolve_ssh_params
      # silently changes the target user after auth.
      @resolved_ssh =
        if local_mode?
          {}
        else
          resolve_ssh_params(params)
        end

      authorize_terminal!(params)
      enforce_rate_limit!
      enforce_max_sessions!

      unless valid_params?
        reject
        return
      end

      start_shell
      register_self
      on_session_start
    rescue GhosttyRails::UnauthorizedError
      reject
    rescue GhosttyRails::RateLimitedError
      reject
    end

    def unsubscribed
      on_session_end
      deregister_self
      stop_shell
    end

    private

    # Override in your subclass to enforce
    # authorization. Raise
    # GhosttyRails::UnauthorizedError to reject
    # the subscription.
    #
    # By default, when require_explicit_authorization
    # is true (the default), this method:
    #   - In production: raises UnauthorizedError,
    #     requiring you to override it.
    #   - In development/test: logs a warning but
    #     permits the connection.
    #
    # Set config.require_explicit_authorization =
    # false to restore the old permit-all behavior.
    def authorize_terminal!(_params)
      return unless config
                    .require_explicit_authorization

      if defined?(::Rails) && ::Rails.env.production?
        log_warn(
          'authorize_terminal! not overridden ' \
          'in production -- rejecting. Subclass ' \
          'this channel and implement authorization.'
        )
        raise GhosttyRails::UnauthorizedError
      elsif defined?(::Rails)
        log_warn(
          'authorize_terminal! not overridden. ' \
          'In production this will reject. ' \
          'Override in your TerminalChannel subclass.'
        )
      end
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

    def deregister_self
      return unless @session_id

      self.class.send(
        :deregister_session, @session_id
      )
    end

    def enforce_max_sessions!
      max = config.max_sessions
      return unless max

      return unless self.class.session_count >= max

      log_warn(
        "max sessions (#{max}) reached, " \
        'rejecting new terminal'
      )
      raise GhosttyRails::UnauthorizedError
    end

    # Enforce rate limiting for new session
    # creation. Uses a class-level sliding window
    # keyed by rate_limit_key (override to
    # customize). Raises RateLimitedError when the
    # limit is exceeded.
    def enforce_rate_limit!
      limit = config.rate_limit
      return unless limit

      key = rate_limit_key
      period = config.rate_limit_period

      count = self.class.send(
        :rate_limit_count, key, period
      )

      if count >= limit
        log_warn(
          "rate limit (#{limit}/#{period}s) " \
          "exceeded for #{key}, rejecting"
        )
        raise GhosttyRails::RateLimitedError
      end

      self.class.send(
        :record_rate_limit_event, key
      )
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

    # Override in your subclass to hook into
    # terminal input before it reaches the PTY.
    # Useful for audit logging, input filtering,
    # or command interception.
    #
    # Runs inside the receive mutex -- keep it
    # fast or offload to a background job.
    def on_input(_data, _params)
      # no-op: override in your app's subclass
    end

    # Override in your subclass to hook into
    # terminal output before it is transmitted
    # to the client. Useful for audit logging
    # or output filtering.
    #
    # Runs inside the reader thread -- keep it
    # fast or offload to a background job.
    def on_output(_data, _params)
      # no-op: override in your app's subclass
    end

    # Called after a session is fully started
    # (PTY spawned, registered). Override in your
    # subclass to set up recording, notify
    # observers, etc. The session_id, params, and
    # connection are all available.
    def on_session_start
      # no-op: override in your app's subclass
    end

    # Called when a session is ending (before
    # deregistration and PTY cleanup). Override
    # to finalize recordings, flush logs, etc.
    def on_session_end
      # no-op: override in your app's subclass
    end

    # Returns a string identifying the current
    # connection for rate limiting and per-user
    # session tracking. Defaults to the
    # ActionCable connection identifier.
    #
    # Override to key on your own user model:
    #
    #   def connection_identifier
    #     current_user.id.to_s
    #   end
    def connection_identifier
      connection.connection_identifier
    end

    # Returns the key used for rate limiting.
    # Defaults to connection_identifier so rate
    # limits are per-user. Override if you want
    # a different grouping (e.g., per-IP).
    def rate_limit_key
      connection_identifier
    end

    def read_loop
      loop do
        break if @stopping

        readable = @mutex.synchronize { @shell_read }
        break unless readable

        begin
          data = readable.read_nonblock(4096)
          data.force_encoding('UTF-8')
          on_output(data, params)
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

    def register_self
      self.class.send(
        :register_session, @session_id, {
          session_id: @session_id,
          channel: self,
          connection_identifier:
            connection_identifier,
          mode: params[:mode].to_s,
          pid: @shell_pid,
          started_at: Time.now
        }
      )
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
    # NOTE: This is called *before*
    # authorize_terminal! so the authorization
    # hook can inspect the resolved params via
    # @resolved_ssh.
    #
    # The default implementation returns an empty
    # hash, which means the channel will fall back
    # to the user/host/port from the subscription
    # params and no identity file.
    def resolve_ssh_params(_params)
      {}
    end

    # Returns the pre-resolved SSH params that
    # were computed before authorization. Available
    # inside authorize_terminal! for inspection.
    def resolved_ssh
      @resolved_ssh || {}
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

      # Use @resolved_ssh which was computed before
      # authorization, not a second call to
      # resolve_ssh_params. This ensures the SSH
      # user actually connecting is the same one
      # that was authorized.
      resolved = resolved_ssh
      user = effective_ssh_user
      user = 'root' if user.empty?

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

    # Allowlist: hostnames, IPv4, IPv6 (bracketed
    # or bare), and simple patterns like
    # "host.example.com" or "10.0.0.1".
    VALID_SSH_HOST = /\A[a-zA-Z0-9.\-:\[\]]+\z/
    private_constant :VALID_SSH_HOST

    # Allowlist for SSH usernames. Permits
    # alphanumerics, dots, hyphens, underscores.
    VALID_SSH_USER = /\A[a-zA-Z0-9._-]+\z/
    private_constant :VALID_SSH_USER

    def valid_ssh_params?
      host = params[:ssh_host].to_s.strip
      return false if host.empty?
      return false unless VALID_SSH_HOST.match?(host)

      user = effective_ssh_user
      if !user.empty? && !VALID_SSH_USER
         .match?(user)
        return false
      end

      auth = params[:ssh_auth_method].to_s
      return false unless ALLOWED_AUTH_METHODS
                          .include?(auth)

      true
    end

    # Returns the SSH user that will actually be
    # used, after considering param and resolved
    # values. Empty string when no user is set
    # (will default to 'root' later in
    # ssh_command).
    def effective_ssh_user
      user = params[:ssh_user].to_s.strip
      return user unless user.empty?

      resolved_ssh[:user].to_s.strip
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
