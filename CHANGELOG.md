# Changelog

## 0.1.0 (unreleased)

- Initial release.
- `GhosttyRails::TerminalChannel` base class with
  PTY spawning, read loop, resize, and SIGTERM/KILL
  process lifecycle.
- Local shell and SSH session modes.
- `authorize_terminal!` hook for pluggable auth.
- Default-secure authorization: rejects in
  production unless overridden.
- `resolve_ssh_params` hook for SSH identity
  resolution (called before authorization).
- `connection_identifier` override for per-user
  keying of rate limits and session tracking.
- Rate limiting with configurable sliding window
  (`rate_limit`, `rate_limit_period`).
- Global session cap (`max_sessions`).
- Thread-safe session registry with query and
  force-disconnect APIs.
- I/O hooks: `on_input`, `on_output`,
  `on_session_start`, `on_session_end`.
- SSH host and user allowlist validation (rejects
  shell metacharacters via regex allowlist).
- UTF-8 scrubbing of PTY output.
- Guard against nil input data and rejected-
  subscription hook invocation.
- Rescue `PTY.spawn` failures cleanly.
- Stimulus controllers for terminal rendering and
  fullscreen toggle.
- Ten built-in color themes.
- Rails generator for initial setup.
- Generator creates ActionCable boilerplate
  (connection, channel, cable.yml) if missing.
- Generator moved to standard Rails path so
  `bin/rails generate ghostty_rails:install` works.
- Pre-built `dist/` shipped in gem so consumers
  need no TypeScript build step.
- Removed unused engine asset path initializer.
- Stimulus target guards prevent crashes when
  optional DOM elements are absent.
- README: peer dependency table, copy-paste HTML
  snippet, SSH host key policy docs.
- Devise integration: cookie-based fallback for
  ActionCable auth when Warden middleware is not
  available on WebSocket upgrades.
