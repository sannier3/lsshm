# shellcheck shell=bash
# shellcheck disable=SC2034  # variables consumed by sourced library functions
# Tests for server_config.sh parsing and label helpers.

# Force file-based parsing (no sshd binary in the test environment).
LSSHM_SSHD_BIN=""
LSSHM_SSHD_CONFIG="$LSSHM_TESTS_DIR/fixtures/sshd_config"

assert_eq "2222" "$(lsshm_config_parse_value port)" "port parsed from fixture"
assert_eq "prohibit-password" "$(lsshm_config_parse_value permitrootlogin)" "PermitRootLogin parsed"
assert_eq "no" "$(lsshm_config_parse_value passwordauthentication)" "PasswordAuthentication parsed"

assert_eq "interdit" "$(lsshm_rootlogin_label no)" "root label: no"
assert_eq "clé uniquement" "$(lsshm_rootlogin_label prohibit-password)" "root label: prohibit-password"
assert_eq "clé ou mot de passe" "$(lsshm_rootlogin_label yes)" "root label: yes"
assert_eq "commandes imposées" "$(lsshm_rootlogin_label forced-commands-only)" "root label: forced"

assert_eq "oui" "$(lsshm_yesno_label yes)" "yesno: yes -> oui"
assert_eq "non" "$(lsshm_yesno_label no)" "yesno: no -> non"

# Port is defined before the Include line in the fixture.
assert_true "lsshm_config_defined_before_include port" "port defined before Include"
# KexAlgorithms is not defined at all.
assert_false "lsshm_config_defined_before_include kexalgorithms" "kex not defined before Include"
