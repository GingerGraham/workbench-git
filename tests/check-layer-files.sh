#!/usr/bin/env bash
# tests/check-layer-files.sh — workbench-git
# Static checks on the files workbench-core layers into ~/.gitconfig
# (workbench-core docs/decisions-log.md D82): both parse as git config, the
# defaults never set an identity, and the adopt file is raw key/value lines.
# Plain bash, numbered OK:/FAIL: checks, no framework.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

if ! command -v git &>/dev/null; then
    echo "SKIP: git not installed"
    exit 0
fi

for f in files/gitconfig files/gitconfig-contexts; do
    if git config --file "${REPO_ROOT}/${f}" --list >/dev/null 2>&1; then
        ok "${f} parses as git config"
    else
        fail "${f} does not parse: $(git config --file "${REPO_ROOT}/${f}" --list 2>&1 | head -n 1)"
    fi
    if git config --file "${REPO_ROOT}/${f}" --get-regexp '^user\.' >/dev/null 2>&1; then
        fail "${f} sets user.* — identity is yours, never a layer's"
    else
        ok "${f} sets no user.*"
    fi
done

# The defaults layer is 'under': it must not include anything that could
# override a user's own setting from below.
if git config --file "${REPO_ROOT}/files/gitconfig" --get-all include.path >/dev/null 2>&1; then
    fail "files/gitconfig includes another file — keep includes in files/gitconfig-contexts"
else
    ok "files/gitconfig includes nothing"
fi

ADOPT="${REPO_ROOT}/files/legacy/gitconfig-hook"
if [[ -f "${ADOPT}" ]]; then
    bad=0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        # exactly '<section.key> <value>': two fields, the key dotted, no comment
        if ! [[ "${line}" =~ ^[A-Za-z][A-Za-z0-9-]*\.[A-Za-z][A-Za-z0-9-]*\ [^[:space:]]+$ ]]; then
            fail "files/legacy/gitconfig-hook: not '<key> <value>': '${line}'"
            bad=1
        fi
    done < "${ADOPT}"
    [[ "${bad}" -eq 0 ]] && ok "files/legacy/gitconfig-hook: every line is exactly a key and a value"
else
    fail "files/legacy/gitconfig-hook is missing"
fi

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
[[ "${FAILED}" -eq 0 ]]
