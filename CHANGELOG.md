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
