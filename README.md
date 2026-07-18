**__Readme Languages__** [![English](https://img.shields.io/badge/lang-English-blue.svg)](README.md) [![Français](https://img.shields.io/badge/lang-Français-lightgrey.svg)](README.fr.md) ![License](https://img.shields.io/badge/License-MIT-success?style=flat-square)

# LSSHM - Local SSH Manager

LSSHM is a **local** OpenSSH management tool: SSH server, incoming access, outgoing keys, and remote hosts. It works immediately on the machine where it runs, **with no remote host configured**.

Default dependency-free CLI and optional `dialog` interface.

> [!WARNING]
> LSSHM is under active development (v0.2.0). Incorrect SSH configuration can lock you out of the machine. LSSHM aims to reduce that risk through validation, backups, confirmations, and automatic rollback.

## Scope

LSSHM manages four separate areas, visible in every menu:

| Area | Files involved |
| ---- | -------------- |
| Local SSH server | `/etc/ssh/sshd_config` and includes |
| Incoming access | `~/.ssh/authorized_keys` |
| Outgoing keys | `~/.ssh/id_*`, `ssh-agent` |
| Remote hosts | `~/.ssh/config`, `~/.ssh/known_hosts` |

## Installation

### Linux

Installs LSSHM into `~/.local` and creates the `lsshm` command:

```bash
curl -fsSL https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.sh | bash -s -- install
```

Then run:

```bash
export PATH="$HOME/.local/bin:$PATH"   # once, in the current terminal
lsshm
```

Future SSH sessions will load the PATH automatically (`~/.profile`).

> No `sudo` required for installation. Root privileges are only requested to manage the SSH server or system files.

### Windows (PowerShell)

Download and run the PowerShell CLI (same menus and concepts as Linux):

```powershell
irm https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.ps1 -OutFile $env:TEMP\lsshm.ps1
powershell -ExecutionPolicy Bypass -File $env:TEMP\lsshm.ps1
```

Or install into the user profile:

```powershell
powershell -ExecutionPolicy Bypass -File $env:TEMP\lsshm.ps1 install
```

OpenSSH Server operations require an **elevated** PowerShell session. User keys and `~\.ssh\config` do not.

## Run without installing

To **try** LSSHM or run a **one-off command** without installing anything:

```bash
curl -fsSL https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.sh | bash              # menu
curl -fsSL https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.sh | bash -s -- status   # status
curl -fsSL https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.sh | bash -s -- ui       # dialog UI
```

It is the **same file** as installation; the script is executed directly (re-downloaded on every `curl`).

## Usage

### Interactive menu

```bash
lsshm
```

Shows local status (server, port, root, keys, hosts) then the main menu.

### Dialog interface

```bash
lsshm ui
lsshm --ui          # alias
```

If `dialog` is missing, LSSHM offers to install it or fall back to the CLI.

### Non-interactive commands

```bash
lsshm status
lsshm doctor
lsshm audit
lsshm update
lsshm update rollback
lsshm uninstall
```

#### Local SSH server

```bash
lsshm server status|install|start|stop|restart|reload|enable|disable
lsshm server config|test|logs
```

#### Incoming access (keys allowed **on this machine**)

```bash
lsshm access list [--user root]
lsshm access add [--user jb]
lsshm access remove [--user jb]
lsshm access disable [--user jb]
lsshm access repair [--user jb]
```

#### Local keys (to connect **elsewhere**)

```bash
lsshm key list|generate
lsshm key inspect ~/.ssh/id_ed25519
lsshm key export ~/.ssh/id_ed25519
lsshm key delete ~/.ssh/id_ed25519
lsshm key agent list|add PATH|remove PATH
```

#### Remote hosts (optional)

```bash
lsshm host list|add
lsshm host edit|delete|test|connect|copy-key|revoke-key NAME
```

Global options: `--user NAME`, `-y`, `--no-color`, `-h`.

## Features (v0.2.0)

- Debian / derivatives, systemd, and LXC detection
- OpenSSH Server installation and service management
- Configuration via `/etc/ssh/sshd_config.d/00-lsshm.conf`
- Effective config reading (`sshd -T`) and validation (`sshd -t`)
- Human-readable `PermitRootLogin`, passwords, public keys, `AllowUsers` / `AllowGroups`
- Automatic rollback for dangerous changes (port, root, passwords…)
- `authorized_keys` management (list, add, remove, disable, repair, duplicates)
- ED25519/RSA generation, `ssh-agent`, `~/.ssh/config`, `ssh-copy-id`
- Security audit, logs, backup/restore
- Safe self-update (`bash -n`, SHA-256, atomic replace, rollback)

## Development

From a local clone:

```bash
bash scripts/build.sh
bash lsshm.sh install    # or: bash install.sh
bash tests/run.sh
```

Layout: modules in `src/`, single `lsshm.sh` built by `scripts/build.sh`.

See `CONTRIBUTING.md` and `CHANGELOG.md`.

## Security

LSSHM never transmits private keys. Report vulnerabilities through GitHub (see `SECURITY.md`), not public issues.

## License

MIT — see `LICENSE`.
