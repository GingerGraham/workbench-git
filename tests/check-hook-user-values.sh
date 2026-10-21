#!/usr/bin/env bash
# tests/check-hook-user-values.sh — workbench-git
# Plain bash, numbered OK:/FAIL: checks, matching workbench-core's
# tests/check-*.sh convention (no framework).
#
# workbench-core D81 (Phase 1, interim): hooks/post-deploy.sh used to set
# core.excludesfile/core.attributesfile unconditionally, replacing any value
# the user chose. It now sets each only when unset, already workbench's, or
# pointing at a byte-identical copy of workbench's file (a dotfiles-era
# path) — and otherwise keeps the user's value and says so.
#
# SC2088: '~/...' is quoted on purpose — git stores a user's value with a
#         literal ~, and that unexpanded form is what's under test.
# shellcheck disable=SC2088
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/post-deploy.sh"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
unset GIT_CONFIG_GLOBAL

# fresh_home <name> — an empty $HOME with workbench-git's deployed static
# files in place, as the engine leaves them before the hook runs.
fresh_home() {
    export HOME="${WORK}/$1"
    STATIC_DIR="${HOME}/.local/share/workbench/modules/git/files"
    mkdir -p "${STATIC_DIR}"
    cp "${REPO_ROOT}/files/ignore" "${STATIC_DIR}/ignore"
    cp "${REPO_ROOT}/files/attributes" "${STATIC_DIR}/attributes"
}

# ── 1. Fresh HOME: both values set to workbench's static files. ────────────
fresh_home fresh
bash "${HOOK}" >/dev/null 2>&1
if [[ "$(git config --global --get core.excludesfile)" == "${STATIC_DIR}/ignore" \
    && "$(git config --global --get core.attributesfile)" == "${STATIC_DIR}/attributes" ]]; then
    ok "fresh HOME: core.excludesfile and core.attributesfile are set"
else
    fail "fresh HOME: values not set as expected"
fi

# ── 2. The user's own core.excludesfile is kept, with a message. ───────────
fresh_home user-own
echo "*.mine" > "${HOME}/.my-ignore"
git config --global core.excludesfile "~/.my-ignore"
out="$(bash "${HOOK}" 2>&1)"
if [[ "$(git config --global --get core.excludesfile)" == "~/.my-ignore" ]]; then
    ok "the user's own core.excludesfile is kept"
else
    fail "the user's core.excludesfile was replaced: $(git config --global --get core.excludesfile)"
fi
if grep -q "keeping your core.excludesfile (~/.my-ignore)" <<< "${out}"; then
    ok "the hook says it kept the user's value and where workbench's is"
else
    fail "no 'keeping your core.excludesfile' message: ${out}"
fi
if [[ "$(git config --global --get core.attributesfile)" == "${STATIC_DIR}/attributes" ]]; then
    ok "the other, unset key is still set"
else
    fail "core.attributesfile not set alongside a kept excludesfile"
fi

# ── 3. A path whose file is byte-identical to workbench's is replaced. ─────
fresh_home identical
mkdir -p "${HOME}/.config/dotfiles-era"
cp "${REPO_ROOT}/files/ignore" "${HOME}/.config/dotfiles-era/ignore"
git config --global core.excludesfile "~/.config/dotfiles-era/ignore"
bash "${HOOK}" >/dev/null 2>&1
if [[ "$(git config --global --get core.excludesfile)" == "${STATIC_DIR}/ignore" ]]; then
    ok "a byte-identical copy of workbench's ignore file is replaced with the static path"
else
    fail "byte-identical path not replaced: $(git config --global --get core.excludesfile)"
fi

# ── 4. Idempotent: a second run changes nothing. ───────────────────────────
before="$(cat "${HOME}/.gitconfig")"
bash "${HOOK}" >/dev/null 2>&1
if [[ "$(cat "${HOME}/.gitconfig")" == "${before}" ]]; then
    ok "re-running the hook leaves ~/.gitconfig unchanged"
else
    fail "a second run changed ~/.gitconfig"
fi

echo
if [[ "${FAILED}" -eq 0 ]]; then
    echo "All ${check_no} checks passed."
    exit 0
else
    echo "${FAILED} of ${check_no} checks failed."
    exit 1
fi
