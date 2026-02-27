# Changelog

## 0.1.0 (unreleased)

- Initial release.
- `GhosttyRails::TerminalChannel` base class with
  PTY spawning, read loop, resize, and SIGTERM/KILL
  process lifecycle.
- Local shell and SSH session modes.
- `authorize_terminal!` hook for pluggable auth.
- `resolve_ssh_params` hook for SSH identity
  resolution.
- Stimulus controllers for terminal rendering and
  fullscreen toggle.
- Ten built-in color themes.
- Rails generator for initial setup.
