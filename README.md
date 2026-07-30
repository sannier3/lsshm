**__Readme Languages__** [![English](https://img.shields.io/badge/lang-English-blue.svg)](README.md) [![Français](https://img.shields.io/badge/lang-Français-lightgrey.svg)](README.fr.md) ![License](https://img.shields.io/badge/License-MIT-success?style=flat-square)

# LSSHM - Local SSH Manager

LSSHM is a **local** OpenSSH management tool: SSH server, incoming access, outgoing keys, and remote hosts. It works immediately on the machine where it runs, **with no remote host configured**.

Default dependency-free CLI and optional `dialog` interface.

> [!WARNING]
> LSSHM is under active development (v0.4.1). Incorrect SSH configuration can lock you out of the machine. LSSHM aims to reduce that risk through validation, backups, confirmations, and automatic rollback.

## Languages

LSSHM is fully internationalized. English is the default; French and Spanish are built in. At install time (and on first run) LSSHM asks which language to use, pre-selected from your system locale, and remembers the choice. Change it anytime from the **Settings** menu or per command:

```bash
lsshm --lang en        # Linux (en, fr, es)
```

```powershell
.\lsshm.ps1 -Lang fr   # Windows (en, fr, es)
```

Untranslated strings automatically fall back to English.

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

Installs LSSHM into `~/.local`, creates the `lsshm` command, and configures `~/.local/bin` in your PATH automatically (`~/.profile`, and `~/.bashrc` when present):

```bash
curl -fsSL https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.sh | bash -s -- install
```

Then run:

```bash
lsshm
```

If `lsshm` is not found in the **current** terminal (for example after `curl | bash`, which cannot update the parent shell), open a new terminal, or once:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

> No `sudo` required for installation. Root privileges are only requested to manage the SSH server or system files.

### Windows (PowerShell)

Download and run the PowerShell CLI (same menus and concepts as Linux):

```powershell
irm https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.ps1 -OutFile $env:TEMP\lsshm.ps1
powershell -ExecutionPolicy Bypass -File $env:TEMP\lsshm.ps1
```

Or install into the user profile (adds the install directory to the user PATH automatically):

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

Global options: `--user NAME`, `--lang CODE`, `-y`, `--no-color`, `-h`.

### Administer another user (root / Debian)

As **root** (console, LXC, or `sudo`), LSSHM asks which user to manage for personal SSH files (`~/.ssh`: keys, `authorized_keys`, `config`). A direct root session preselects **root**; a `sudo` session preselects the **calling user** (option 2 lets you pick another account, including root). The system SSH server is still managed as root.

```bash
sudo lsshm
lsshm --user jb access list
lsshm --user jb key generate
```

You can also switch the target user from **Access**, **Keys**, or **Settings**.

## Features (v0.4.1)

- Multilingual UI (English, French, Spanish) with locale-based pre-selection
- Debian / derivatives, systemd, and LXC detection
- OpenSSH Server installation and service management (Linux and Windows)
- Listening settings: `Port`, `AddressFamily`, `ListenAddress`
- Windows Firewall: allow / disable OpenSSH (Server and Client)
- Configuration via `/etc/ssh/sshd_config.d/00-lsshm.conf` (Linux) or `%ProgramData%\ssh\sshd_config` (Windows)
- Effective config reading (`sshd -T`) and validation (`sshd -t`)
- Human-readable `PermitRootLogin`, passwords, public keys, `AllowUsers` / `AllowGroups`
- Automatic rollback for dangerous changes (port, listen addresses, root, passwords…)
- `authorized_keys` management (list, add, remove, disable, repair, duplicates)
- ED25519/RSA generation, `ssh-agent`, `~/.ssh/config`, `ssh-copy-id`
- `known_hosts` management, including repair when a remote host key has changed
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
