# Security Policy

## Project status

LSSHM is currently under active development.

Development versions may contain incomplete features, configuration errors, or behaviours that can interrupt SSH access. Do not use an unreleased version on a production system without console, hypervisor, or physical recovery access.

## Supported versions

Only the latest stable release is intended to receive security updates.

| Version                  | Supported    |
| ------------------------ | ------------ |
| Latest stable release    | Yes          |
| Previous stable releases | Best effort  |
| Development branch       | No guarantee |
| Unofficial forks         | No           |

Until the first stable release is published, all versions should be considered development versions.

## Reporting a vulnerability

Do not report security vulnerabilities in a public GitHub issue, discussion, pull request, or social media post.

Use GitHub private vulnerability reporting for this repository.

Include the following information when possible:

* A description of the vulnerability
* The affected LSSHM version
* The affected operating system
* The affected OpenSSH version
* The commands or menu actions required to reproduce the issue
* The expected behaviour
* The actual behaviour
* The potential security impact
* Relevant logs with secrets removed
* A suggested correction, when available

Do not include:

* Private SSH keys
* Passwords
* Recovery codes
* Access tokens
* Real public IP addresses
* Production hostnames
* Complete production configuration files
* Personally identifiable information

## Security-sensitive areas

Reports are especially important when they involve:

* Exposure of private keys
* Incorrect `authorized_keys` permissions
* Command injection
* Shell argument injection
* Privilege escalation
* Unsafe use of `sudo`
* Arbitrary file writes
* Symbolic link attacks
* Temporary file vulnerabilities
* Incorrect ownership changes
* Unsafe configuration parsing
* SSH configuration corruption
* Failure of automatic rollback
* Authentication settings not matching user choices
* Unintended root access
* Removal of the last valid authentication method
* Update mechanism compromise
* Download integrity failures

## Security design requirements

LSSHM should:

1. Validate SSH server configuration before applying it.
2. Create a backup before every sensitive modification.
3. Avoid executing arbitrary user-provided shell commands.
4. Quote and validate every shell argument.
5. Use secure temporary files.
6. Check file ownership and permissions.
7. Never transmit or upload private keys.
8. Never display private key contents without an explicit warning.
9. Verify effective OpenSSH settings after changes.
10. Provide a recovery path for dangerous operations.
11. Require explicit confirmation before removing an access method.
12. Avoid running the entire application with elevated privileges when unnecessary.
13. Verify downloaded updates before replacing the installed version.
14. Preserve the previous executable during updates.
15. Refuse to apply a configuration that fails validation.

## Responsible disclosure

Please allow maintainers to investigate and correct a confirmed vulnerability before publishing technical details.

A security advisory may be published after a correction is available.

Contributors who report valid vulnerabilities may be credited in the advisory unless they request anonymity.

## Operational recommendations

Before using LSSHM on a remote system:

* Keep an active SSH session open
* Verify that console or hypervisor access is available
* Create a system backup or snapshot
* Confirm that at least one administrative user has a valid public key
* Test a second SSH connection before closing the original session
* Do not disable password authentication until key authentication has been tested
* Do not change the SSH port without checking the firewall
* Do not disable root access until another administrative account has been tested

## Disclaimer

LSSHM manages security-sensitive system configuration.

No tool can guarantee that a configuration change will not interrupt access. Users remain responsible for maintaining an independent recovery method and reviewing changes before applying them.
