#!/usr/bin/env bash
# tests/check-manifest-structure.sh — workbench-git
# Plain bash, numbered OK:/FAIL: checks, matching workbench-core's
# tests/check-*.sh convention (no framework). Structural checks only — this
# repo doesn't carry a full copy of workbench-core's sync engine to test
# against, so these check what can be verified standalone: the manifest's
# declared files actually exist, hooks are executable, and the shell surface
# stays bash-3.2 compatible.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${REPO_ROOT}/.dotfiles-sync.yml"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

[[ -f "${MANIFEST}" ]] && ok ".dotfiles-sync.yml exists" || fail ".dotfiles-sync.yml missing"

for key in version core_api register deploy hooks; do
    if grep -q "^${key}:" "${MANIFEST}"; then
        ok "manifest declares '${key}:'"
    else
        fail "manifest missing '${key}:'"
    fi
done

# Every deploy[].src and register.shell[].src/register.installers[].src
# referenced in the manifest must exist on disk.
_missing=0
while IFS= read -r src; do
    [[ -z "${src}" ]] && continue
    if [[ -f "${REPO_ROOT}/${src}" ]]; then
        ok "referenced file exists: ${src}"
    else
        fail "manifest references missing file: ${src}"
        _missing=$((_missing + 1))
    fi
done < <(grep -E '^\s*(-\s*)?src:' "${MANIFEST}" | sed -E 's/^\s*-?\s*src:\s*//')

[[ -x "${REPO_ROOT}/hooks/post-deploy.sh" ]] \
    && ok "hooks/post-deploy.sh is executable" \
    || fail "hooks/post-deploy.sh is not executable"

# Bash 3.2 compatibility — same pattern set as workbench-core's own
# tests/check-bash32-compat.sh.
declare -a _bash32_patterns=(
    "declare -A (associative arrays, bash 4+)|declare[[:space:]]+-A"
    "mapfile/readarray (bash 4+)|(^|[^[:alnum:]_])(mapfile|readarray)([^[:alnum:]_]|\$)"
    "shopt -s globstar (bash 4+)|shopt[[:space:]]+-s[[:space:]]+globstar"
    "\${var,,} / \${var^^} case conversion (bash 4+)|\\\$\\{[a-zA-Z_][a-zA-Z0-9_]*(,,|\\^\\^)"
    "declare -n nameref (bash 4.3+)|declare[[:space:]]+-n"
)
for entry in "${_bash32_patterns[@]}"; do
    desc="${entry%%|*}"
    pattern="${entry#*|}"
    hit=""
    while IFS= read -r -d '' f; do
        grep -vE '^[[:space:]]*#' "${f}" | grep -qE "${pattern}" && hit="${hit}${f}\n"
    done < <(find "${REPO_ROOT}/shell" "${REPO_ROOT}/hooks" -type f -print0 2>/dev/null)
    if [[ -n "${hit}" ]]; then
        fail "found ${desc} in: $(printf '%b' "${hit}" | tr '\n' ' ')"
    else
        ok "no ${desc}"
    fi
done

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
[[ "${FAILED}" -eq 0 ]]
