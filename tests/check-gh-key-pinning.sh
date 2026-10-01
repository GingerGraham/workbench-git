#!/usr/bin/env bash
# tests/check-gh-key-pinning.sh — workbench-git
# Plain bash, numbered OK:/FAIL: checks, matching workbench-core's
# tests/check-*.sh convention (no framework).
#
# Security review follow-up R1/R2 (workbench-core D79): install-gh trusts
# only the pinned GitHub CLI key(s), via core's Core API 1.5 helpers, never
# by importing the downloaded key file. This suite stubs those helpers and
# checks what shell/installers.sh hands them. The same driver runs under
# bash and, when installed, zsh: a space-separated fingerprint string does
# not word-split in zsh, so it must arrive as one fingerprint per argument.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="${REPO_ROOT}/shell/installers.sh"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

FPR_OLD="2C6106201985B60E6C7AC87323F3D4EA75716059"
FPR_NEW="7F38BBB59D064DBCB3D84D725612B36462313325"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# Static checks: the three unpinned helpers are gone.
if grep -rn '_gh_key_fingerprint_ok\|_gh_import_verified_key\|_gh_repo_gpgkey_and_id\|_gh_dnf_is_v5' "${REPO_ROOT}/shell" >/dev/null; then
    fail "removed helpers still referenced under shell/"
else
    ok "no reference to _gh_key_fingerprint_ok/_gh_import_verified_key/_gh_repo_gpgkey_and_id/_gh_dnf_is_v5"
fi
if grep -n 'rpm --import' "${SRC}" >/dev/null; then
    fail "shell/installers.sh still calls rpm --import directly"
else
    ok "shell/installers.sh never calls rpm --import directly"
fi

# Driver, sourced by whichever shell is under test. Prints one line per
# helper invocation: "<helper> <arg>|<arg>|...". "$1" = which installer;
# "$2" = repo id served by the stubbed .repo file.
cat > "${WORK}/driver.sh" <<'DRIVER'
log_info() { :; }
log_warn() { :; }
log_error() { echo "ERR $*"; }
get-elevation-command() { echo stubsudo; }
stubsudo() { "$@"; }
dnf() { :; }
yum() { :; }
zypper() { :; }
apt-get() { :; }
dpkg() { echo amd64; }
mkdir() { :; }
tee() { cat >/dev/null; }
curl() {
    printf '%s\n' "[${STUB_REPO_ID}]" 'name=gh-cli' \
        'baseurl=https://cli.github.com/packages/rpm' 'enabled=1' 'gpgcheck=1' \
        'gpgkey=https://cli.github.com/packages/githubcli-archive-keyring.gpg'
}
_wb_vendor_id_is_valid() {
    case "$1" in ''|*[!a-z0-9._-]*) return 1 ;; *) return 0 ;; esac
}
_show() { local IFS='|'; echo "$*"; }
_wb_dnf_vendor_repo()      { echo "dnf_vendor_repo $(_show "$@")"; }
# The caller discards this helper's stdout (it prints the installed path), so
# report on stderr; run_driver merges the two.
_wb_rpm_import_pinned_key() { echo "rpm_import $(_show "$@")" >&2; }
_wb_apt_keyring_pinned()   { echo "apt_keyring $(_show "$@")"; }
# shellcheck disable=SC1090
. "${SRC}"
case "$1" in
    rhel)   _gh-install-rhel ;;
    suse)   _gh-install-suse ;;
    debian) _gh-install-debian ;;
esac
DRIVER

run_driver() { # <shell> <installer> <repo-id>
    # shellcheck disable=SC2016  # $0/$@ are for the inner shell, deliberately unexpanded
    SRC="${SRC}" STUB_REPO_ID="$3" "$1" -c '. "$0" "$@"' "${WORK}/driver.sh" "$2" 2>&1
}

run_suite() { # <shell>
    local sh="$1" out
    command -v "${sh}" >/dev/null 2>&1 || { echo "SKIP: ${sh} not installed — fingerprint-array checks not run under it"; return 0; }

    if [[ -f /etc/fedora-release ]]; then
        echo "SKIP: [${sh}] rhel check (Fedora host takes the distro-package early return)"
    else
        out="$(run_driver "${sh}" rhel gh-cli)"
        case "${out}" in
            *"--id|gh-cli|"*"--baseurl|https://cli.github.com/packages/rpm|--key-url|https://cli.github.com/packages/githubcli-archive-keyring.gpg|--fingerprint|${FPR_OLD}|--fingerprint|${FPR_NEW}|--include|gh"*)
                ok "[${sh}] rhel: vendor repo gets id, baseurl, key URL, one --fingerprint per pinned key, --include gh" ;;
            *) fail "[${sh}] rhel: unexpected _wb_dnf_vendor_repo arguments: ${out}" ;;
        esac

        out="$(run_driver "${sh}" rhel 'bad id')"
        case "${out}" in
            *"not a valid repo id"*) ok "[${sh}] rhel: invalid repo id from the .repo file is rejected" ;;
            *) fail "[${sh}] rhel: invalid repo id not rejected: ${out}" ;;
        esac
    fi

    out="$(run_driver "${sh}" suse gh-cli)"
    case "${out}" in
        "rpm_import https://cli.github.com/packages/githubcli-archive-keyring.gpg|gh-cli|${FPR_OLD}|${FPR_NEW}")
            ok "[${sh}] suse: pinned import gets key URL, repo id and two separate fingerprints" ;;
        *) fail "[${sh}] suse: unexpected _wb_rpm_import_pinned_key arguments: ${out}" ;;
    esac

    out="$(run_driver "${sh}" debian gh-cli)"
    case "${out}" in
        "apt_keyring https://cli.github.com/packages/githubcli-archive-keyring.gpg|/etc/apt/keyrings/githubcli-archive-keyring.gpg|${FPR_OLD}|${FPR_NEW}")
            ok "[${sh}] debian: pinned keyring gets key URL, keyring path and two separate fingerprints" ;;
        *) fail "[${sh}] debian: unexpected _wb_apt_keyring_pinned arguments: ${out}" ;;
    esac
}

run_suite bash
run_suite zsh

if [[ ${FAILED} -gt 0 ]]; then
    echo "${FAILED} check(s) failed"
    exit 1
fi
echo "All ${check_no} checks passed"
