# LSSHM - Local SSH Manager

LSSHM is a local OpenSSH management tool designed to make SSH server configuration, user access, SSH keys, and remote host management easier to understand and safer to operate.

It provides a simple command-line interface by default and an optional terminal user interface powered by `dialog`.

LSSHM is designed to manage SSH directly on the machine where it is installed. It does not require a web server, browser, remote service, or cloud account.

> [!WARNING]
> LSSHM is currently under active development and is not yet recommended for production systems.
>
> Incorrect SSH configuration can lock you out of a remote machine. LSSHM aims to prevent this through validation, backups, confirmation prompts, and automatic rollback mechanisms.

## Goals

LSSHM aims to provide one understandable tool for:

* Managing the local OpenSSH server
* Configuring SSH authentication
* Managing access to the local machine
* Managing authorized public keys
* Creating and managing local SSH key pairs
* Managing the SSH agent
* Managing remote SSH hosts
* Validating SSH configuration changes
* Backing up and restoring SSH configuration
* Auditing common SSH security settings

The project is intended for beginners, system administrators, homelab users, technicians, developers, virtual machines, and Linux containers.

## Interfaces

### Command-line interface

The default interface does not require any additional package:

```bash
lsshm
```

### Dialog interface

The optional terminal interface uses `dialog`:

```bash
lsshm ui
```

When `dialog` is not installed, LSSHM can offer to install it using the detected package manager.

The CLI remains available when `dialog` cannot be installed.

## Planned features

### Local OpenSSH server

* Detect whether OpenSSH Server is installed
* Install OpenSSH Server
* Start, stop, restart, and reload the SSH service
* Enable or disable automatic startup
* Display the active SSH port
* Configure listening addresses
* Configure IPv4 and IPv6 listening
* Configure root login
* Enable or disable password authentication
* Enable or disable public key authentication
* Configure keyboard-interactive authentication
* Configure allowed users and groups
* Configure denied users and groups
* Configure login grace time
* Configure maximum authentication attempts
* Configure forwarding, tunnelling, X11, and SFTP
* Display the effective OpenSSH configuration
* Validate configuration before applying changes

### Access to the local machine

* List local users
* Display authorized keys for each user
* Add a public key
* Import a `.pub` file
* Remove a key by fingerprint
* Detect duplicate keys
* Temporarily disable a key
* Add source address restrictions
* Restrict port forwarding
* Restrict agent forwarding
* Restrict X11 forwarding
* Force a command for a specific key
* Repair `.ssh` ownership and permissions

### Local SSH keys

* Detect existing SSH key pairs
* Generate ED25519 keys
* Generate RSA keys for compatibility
* Add or change a passphrase
* Display a public key
* Display a key fingerprint
* Add a key to `ssh-agent`
* Remove a key from `ssh-agent`
* Export a public key
* Safely remove a key pair
* Copy a public key to a remote machine

LSSHM must never transmit or upload private keys.

### Remote SSH hosts

* List hosts from `~/.ssh/config`
* Add a host
* Edit a host
* Remove a host
* Test network connectivity
* Test SSH authentication
* Connect to a host
* Configure hostname, user, port, and identity file
* Configure `ProxyJump`
* Configure local, remote, and dynamic forwarding
* Display the effective client configuration using `ssh -G`
* Manage known host fingerprints
* Remove outdated fingerprints
* Copy a public key using `ssh-copy-id`

Remote hosts are optional. LSSHM must remain fully usable without any host configured.

### Logs and diagnostics

* Display active SSH sessions
* Display recent successful logins
* Display recent failed login attempts
* Display SSH service logs
* Detect common permission errors
* Detect invalid configuration directives
* Detect conflicting configuration files
* Check whether the configured SSH port is listening
* Run a local SSH security audit

### Backup and recovery

* Back up SSH server configuration before every sensitive change
* Back up authorized keys before modification
* Validate configuration using `sshd -t`
* Read effective configuration using `sshd -T`
* Reload SSH instead of restarting it whenever possible
* Keep previous managed configurations
* Restore a previous backup
* Schedule automatic rollback for dangerous changes
* Confirm that a new SSH connection works before cancelling rollback

## Security principles

LSSHM follows these principles:

1. Never apply an invalid SSH server configuration.
2. Never remove the last known access method without explicit confirmation.
3. Never send, upload, or expose a private key.
4. Never overwrite configuration without creating a backup.
5. Never hide the exact OpenSSH values being applied.
6. Prefer a reload over a service restart.
7. Display warnings before dangerous operations.
8. Verify effective settings after changes.
9. Keep local and privileged operations clearly separated.
10. Allow every managed change to be reverted.

## Supported platforms

### Initial target

* Debian
* Debian-based Linux distributions
* Bare-metal Linux systems
* Linux virtual machines
* Linux LXC containers
* Systems using OpenSSH Server
* Systems using systemd, with fallback support planned for other service managers

### Planned support

* Ubuntu
* Alpine Linux
* Red Hat-based distributions
* Arch Linux
* openSUSE
* Windows OpenSSH Server through a dedicated PowerShell implementation

Windows support will use a separate `lsshm.ps1` implementation because Windows OpenSSH paths, services, permissions, firewall rules, and administrator key handling differ from Linux.

## Installation

### Development installation

The following command downloads the current development version from the `main` branch:

```bash
curl -fsSL https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.sh | bash -s -- install
```

Running scripts directly from the Internet should only be done after reviewing the source code.

To review the script before installation:

```bash
curl -fsSL https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.sh -o /tmp/lsshm.sh
less /tmp/lsshm.sh
bash /tmp/lsshm.sh install
```

### Planned installation paths

```text
~/.local/bin/lsshm
~/.local/share/lsshm/lsshm.sh
~/.config/lsshm/config
~/.local/state/lsshm/
~/.cache/lsshm/
```

The installer should add `~/.local/bin` to the user path when necessary.

LSSHM should request elevated privileges only when an operation requires access to system files, services, users, groups, or firewall settings.

## Usage

Open the default CLI menu:

```bash
lsshm
```

Open the `dialog` interface:

```bash
lsshm ui
```

Display local SSH status:

```bash
lsshm status
```

Run diagnostics:

```bash
lsshm doctor
```

Run a security audit:

```bash
lsshm audit
```

Check for updates:

```bash
lsshm update
```

Uninstall LSSHM:

```bash
lsshm uninstall
```

### Planned command structure

```text
lsshm server
lsshm access
lsshm key
lsshm agent
lsshm host
lsshm known-host
lsshm logs
lsshm audit
lsshm backup
lsshm restore
lsshm update
lsshm uninstall
```

Examples:

```bash
lsshm server status
lsshm server config
lsshm server test

lsshm access list
lsshm access add --user jb
lsshm access repair --user jb

lsshm key list
lsshm key generate
lsshm key inspect ~/.ssh/id_ed25519

lsshm host list
lsshm host add
lsshm host test proxmox1
lsshm host connect proxmox1
```

## Files managed on Linux

Depending on the selected operations, LSSHM may inspect or manage:

```text
/etc/ssh/sshd_config
/etc/ssh/sshd_config.d/
~/.ssh/config
~/.ssh/authorized_keys
~/.ssh/known_hosts
~/.ssh/id_*
```

LSSHM should prefer a dedicated managed configuration file instead of rewriting the entire OpenSSH configuration.

Every system-level change must be validated before being applied.

## Project status

The planned development stages are:

### Version 0.1

* Debian detection
* Local installation
* Basic CLI
* OpenSSH Server detection and installation
* SSH service management
* Root login management
* Password and public key authentication
* Configuration validation
* Configuration backups
* Authorized key management
* ED25519 key generation

### Version 0.2

* Complete `dialog` interface
* SSH agent management
* Remote host management
* Known host management
* Logs and diagnostics
* Security audit

### Version 0.3

* Automatic rollback
* Additional Linux distributions
* Firewall integration
* Fail2ban integration
* Release-based self-update system

### Version 0.4

* Windows OpenSSH support
* PowerShell implementation
* Windows service and firewall management

## Development

The final Linux installer may remain available as a single `lsshm.sh` file, while the source code can be split into modules for easier maintenance and testing.

Suggested repository structure:

```text
lsshm/
├── lsshm.sh
├── lsshm.ps1
├── VERSION
├── README.md
├── LICENSE
├── SECURITY.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── src/
│   ├── common.sh
│   ├── platform.sh
│   ├── privileges.sh
│   ├── server.sh
│   ├── server_config.sh
│   ├── authorized_keys.sh
│   ├── local_keys.sh
│   ├── ssh_agent.sh
│   ├── hosts.sh
│   ├── known_hosts.sh
│   ├── logs.sh
│   ├── audit.sh
│   ├── backup.sh
│   ├── rollback.sh
│   ├── updater.sh
│   ├── cli.sh
│   └── dialog.sh
├── scripts/
│   └── build.sh
├── tests/
└── .github/
    └── workflows/
```

## Contributing

Contributions, bug reports, documentation improvements, translations, and platform compatibility reports are welcome.

Before submitting code:

* Run ShellCheck
* Test with a non-production machine
* Validate all generated SSH configurations
* Avoid introducing commands that execute arbitrary input
* Never include private keys, passwords, host credentials, or production configuration in commits or issues

See `CONTRIBUTING.md` for contribution instructions when available.

## Security

Do not report security vulnerabilities through a public issue.

Use GitHub private vulnerability reporting when available. See `SECURITY.md` for details.

## License

LSSHM is licensed under the MIT License.

See the `LICENSE` file for the full license text.

## Disclaimer

LSSHM modifies security-sensitive system configuration.

The maintainers are not responsible for loss of access, configuration damage, data loss, service interruption, or security incidents resulting from the use or misuse of this software.

Always keep an active recovery method, console access, hypervisor access, or a second administrative session before applying SSH configuration changes.
