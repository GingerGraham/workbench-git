#!/usr/bin/env bash
# tests/check-yq-arch-install.sh — workbench-git
# Plain bash, numbered OK:/FAIL: checks, matching workbench-core's
# tests/check-*.sh convention (no framework).
#
# On Arch, install-yq must install mikefarah's yq v4, which Arch packages
# as `go-yq`; Arch's `yq` package is the Python wrapper (kislyuk/yq). It
# goes through pacman from the official repos, never yay, even when yay is
# installed. pacman, yay and the elevation helper are stubbed; nothing is
# installed. The same driver runs under bash and, when installed, zsh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="${REPO_ROOT}/shell/installers.sh"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# A fake yay on PATH, so "yay is installed" is true for command -v.
mkdir -p "${WORK}/bin"
printf '#!/bin/sh\necho "yay $*" >> "%s/calls.log"\n' "${WORK}" > "${WORK}/bin/yay"
chmod +x "${WORK}/bin/yay"

# Driver, sourced by whichever shell is under test. Every stubbed command
# appends "<command> <args>" to calls.log.
cat > "${WORK}/driver.sh" <<'DRIVER'
log_info() { :; }
log_warn() { :; }
log_error() { echo "ERR $*"; }
get-elevation-command() { echo stubsudo; }
stubsudo() { "$@"; }
pacman() { echo "pacman $*" >> "${CALLS_LOG}"; }
source "${SRC}"
_yq-install-arch
echo "rc=$?"
DRIVER

run_driver() {
    local shell="$1"
    : > "${WORK}/calls.log"
    CALLS_LOG="${WORK}/calls.log" SRC="${SRC}" PATH="${WORK}/bin:${PATH}" \
        "${shell}" "${WORK}/driver.sh" >"${WORK}/${shell}.out" 2>&1
}

for shell in bash zsh; do
    if ! command -v "${shell}" &>/dev/null; then
        echo "SKIP: ${shell} not installed"
        continue
    fi
    run_driver "${shell}"

    if grep -qx 'pacman -S --needed --noconfirm go-yq' "${WORK}/calls.log" \
        && grep -qx 'rc=0' "${WORK}/${shell}.out"; then
        ok "${shell}: _yq-install-arch runs 'pacman -S --needed --noconfirm go-yq' and returns 0"
    else
        fail "${shell}: _yq-install-arch did not install go-yq with pacman"
        cat "${WORK}/calls.log" "${WORK}/${shell}.out"
    fi

    if grep -q '^yay' "${WORK}/calls.log"; then
        fail "${shell}: _yq-install-arch called yay although go-yq is in the official repos"
    else
        ok "${shell}: yay is never called, even when installed"
    fi

    # Arch's `yq` is the Python wrapper: it must never be the package asked for.
    if grep -qE '(^| )yq( |$)' "${WORK}/calls.log"; then
        fail "${shell}: _yq-install-arch asked for the 'yq' package (the Python wrapper)"
        cat "${WORK}/calls.log"
    else
        ok "${shell}: the 'yq' package (Python wrapper on Arch) is never requested"
    fi
done

echo
echo "==============================="
echo "Checks run: ${check_no}"
echo "Failed:     ${FAILED}"
echo "==============================="
[[ "${FAILED}" -eq 0 ]]
