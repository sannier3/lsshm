# shellcheck shell=bash
# Tests for hosts.sh parsing against a fixture ssh config.

# Redirect the hosts file to the fixture.
lsshm_hosts_file() { printf '%s/fixtures/ssh_config' "$LSSHM_TESTS_DIR"; }

assert_eq "192.168.100.240" "$(lsshm_hosts_get_field proxmox1 HostName)" "proxmox1 HostName"
assert_eq "root" "$(lsshm_hosts_get_field proxmox1 User)" "proxmox1 User"
assert_eq "2022" "$(lsshm_hosts_get_field backup Port)" "backup Port"

assert_true "lsshm_hosts_exists proxmox1" "proxmox1 exists"
assert_true "lsshm_hosts_exists backup" "backup exists"
assert_false "lsshm_hosts_exists doesnotexist" "unknown host does not exist"

# Wildcard blocks are not counted as concrete hosts.
assert_eq "2" "$(lsshm_hosts_count)" "concrete host count (excludes web-*)"
