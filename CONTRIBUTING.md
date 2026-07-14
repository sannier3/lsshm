# Contributing to LSSHM

Thank you for your interest in improving LSSHM - Local SSH Manager.

## Project layout

LSSHM ships to users as a single file, `lsshm.sh`, but it is developed as a set
of small modules under `src/`. The single file is generated:

```bash
./scripts/build.sh
```

Never edit `lsshm.sh` by hand. Edit the modules in `src/` and rebuild.

```text
src/
├── main.sh          # entry point and command dispatch
├── common.sh        # logging, prompts, colors, temp files, helpers
├── platform.sh      # distribution / service manager / virt detection
├── privileges.sh    # sudo handling and calling-user detection
├── updater.sh       # self-update and rollback
├── server.sh        # OpenSSH server service management
├── server_config.sh # sshd_config parsing and managed drop-in
├── users.sh         # local user helpers
├── authorized_keys.sh # incoming access management
├── local_keys.sh    # local key pair management
├── ssh_agent.sh     # ssh-agent management
├── hosts.sh         # ~/.ssh/config management
├── known_hosts.sh   # known_hosts management
├── logs.sh          # sessions and logs
├── audit.sh         # local security audit
├── backup.sh        # backup and restore
├── rollback.sh      # automatic rollback for dangerous changes
├── cli.sh           # dependency-free CLI menus
└── dialog.sh        # optional dialog interface
```

The build order is defined in `scripts/build.sh`.

## Coding conventions

- Target `bash` 4+ and keep POSIX-friendly habits where practical.
- `set -euo pipefail` is enabled in the assembled script; write functions that
  behave under those options.
- Prefix all public function names with `lsshm_`.
- Quote every variable expansion. Validate and quote all shell arguments.
- Never execute arbitrary user-provided strings as commands.
- Prefer `printf` over `echo` for anything that is not a fixed literal.
- Keep user-facing strings in the CLI clear and unambiguous. Always specify the
  direction of an SSH key (incoming access vs outgoing connection).

## Before submitting

- Run ShellCheck on the modules and the assembled file:

```bash
shellcheck src/*.sh scripts/*.sh
shellcheck lsshm.sh
```

- Validate syntax:

```bash
bash -n lsshm.sh
```

- Run the test suite:

```bash
./tests/run.sh
```

- Test on a non-production machine, VM, or container. Verify that every
  generated SSH configuration passes `sshd -t`.

## Security

Never include private keys, passphrases, real hostnames, public IP addresses,
or production configuration in commits, issues, or pull requests.

See `SECURITY.md` for the vulnerability reporting process.
