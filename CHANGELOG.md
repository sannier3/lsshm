# Changelog

All notable changes to LSSHM are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `install` / `uninstall` / `update` / `version` / `help` / `server` no longer
  prompt for a target user (personal SSH context is irrelevant there).
- Root target-user picker is resilient to `set -e` failures inside `$(prompt)`.

## [0.3.1] - 2026-07-18

### Fixed

- Key listing / picker no longer misses existing `*.pub` pairs (bash array was
  filled inside a subshell via `$(lsshm_keys_collect)`).
- As root, `authorized_keys` writes now always `chown` to the target user
  (StrictModes-safe).
- Rollback archive path no longer polluted by status messages on stdout.
- `host revoke-key` actually sends the key body to the remote (`$1`, not env).
- Host delete/edit and `known_hosts` remove preserve ownership for the managed
  user; edit restores the previous config if add is cancelled.
- `~/` IdentityFile expansion uses the managed user's home, not process `$HOME`.
- Privileged `mkdir` of another user's `~/.ssh` now sets ownership.
- Temp files created inside `$(...)` are tracked for EXIT cleanup; rollback
  scripts use `persist` temps.
- `sshd -T` cache is file-backed so it survives command-substitution subshells.
- Duplicate detection for access add also matches LSSHM-DISABLED entries.

## [0.3.0] - 2026-07-18

### Added

- As root (direct login or sudo), interactive choice of which user's personal
  SSH files to administer (`authorized_keys`, keys, `~/.ssh/config`).
- Target-user picker in Access, Keys, and Settings menus; correct ownership
  when generating keys or editing hosts for another user.

### Fixed

- Opening the menu as a normal user no longer asks for the sudo password
  multiple times: `sshd -T` is cached, status reads fall back to config files,
  and sudo is primed once per session when a privileged action is needed.

## [0.2.0] - 2026-07-18

### Added

- Windows PowerShell CLI (`lsshm.ps1`) with the same menu structure as Linux:
  local SSH server, incoming access, outgoing keys, and remote hosts.
- Windows OpenSSH paths (`%ProgramData%\ssh\`, `administrators_authorized_keys`)
  and `sshd` service management.
- Run-without-install documentation for Linux and Windows in README.

### Fixed

- Fail-closed SHA-256 verification for update and install.
- Dangerous SSH changes always arm automatic rollback (no bypass via `-y`).
- Safe remote key revoke (`host revoke-key`) with literal matching.
- Consistent `authorized_keys` indexing for list / remove / disable.
- `PubkeyAuthentication no` treated as a dangerous change.
- Dialog UI trap preserves temporary-file cleanup.
- CI: executable scripts, tracked `authorized_keys.sh` / `known_hosts.sh`.

## [0.1.0] - 2026-07-14

### Added

- Local user installation under the XDG base directories
  (`~/.local/bin`, `~/.local/share`, `~/.config`, `~/.local/state`, `~/.cache`).
- Single-file distribution (`lsshm.sh`) that acts as program, installer,
  updater, and uninstaller.
- Modular source tree under `src/` assembled by `scripts/build.sh`.
- Dependency-free CLI menu (`lsshm`) split into four clearly separated areas:
  local SSH server, incoming access, local outgoing keys, and remote hosts.
- Optional `dialog` terminal interface (`lsshm ui` / `lsshm --ui`) with an
  offer to install `dialog` when missing.
- Platform detection: distribution, package manager, service manager,
  systemd presence, virtualization type, and `sshd` paths.
- Privilege handling that keeps unprivileged operations without `sudo`
  and detects the calling user through `SUDO_USER`.
- Local OpenSSH server management: detection, installation, start, stop,
  restart, reload, enable, disable, status, config test, and logs.
- Effective configuration reading with `sshd -T` and validation with `sshd -t`.
- Managed drop-in configuration file `00-lsshm.conf` with `Include` and
  early-definition detection.
- Human-readable `PermitRootLogin`, `PasswordAuthentication`,
  `PubkeyAuthentication`, `AllowUsers`, and `AllowGroups` management.
- Automatic rollback for dangerous changes using `systemd-run` with a
  `nohup` fallback.
- Incoming access management (`authorized_keys`): list, add, import, remove,
  disable, comment, permission repair, and duplicate detection.
- Local key management: detection, ED25519/RSA generation, inspection,
  fingerprints, export, passphrase change, and safe deletion.
- `ssh-agent` management: list, add, and remove keys.
- Remote host management through `~/.ssh/config`: list, add, edit, delete,
  test, connect, copy-key, and effective config with `ssh -G`.
- `known_hosts` management: list, show, and remove fingerprints.
- Logs and diagnostics (`lsshm logs`, `lsshm doctor`).
- Local security audit (`lsshm audit`).
- Backup and restore of managed SSH files.
- Safe self-update from the repository (`lsshm update`, `lsshm update rollback`)
  with temporary download, `bash -n` check, SHA-256 verification, atomic
  replacement, and previous-version retention.

[Unreleased]: https://github.com/sannier3/lsshm/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/sannier3/lsshm/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/sannier3/lsshm/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/sannier3/lsshm/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/sannier3/lsshm/releases/tag/v0.1.0
