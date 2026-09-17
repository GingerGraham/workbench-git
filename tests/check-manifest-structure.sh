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

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

# Manifest discovery, duplicated inline rather than sourced from
# workbench-core — this script runs standalone in this module's own CI,
# the same "must work without workbench-core installed alongside it"
# constraint lib/manifest/validate.sh's own header documents for its
# identical duplication (workbench-core ARCHITECTURE.md §12 D46). Checked
# in precedence order; .dotfiles-sync.yml is accepted unconditionally,
# the four new names only if they declare a top-level version: key.
_MANIFEST_CANDIDATES="workbench.yml workbench.yaml wb.yml wb.yaml .dotfiles-sync.yml"
MANIFEST=""
for _name in ${_MANIFEST_CANDIDATES}; do
    _candidate="${REPO_ROOT}/${_name}"
    [[ -f "${_candidate}" ]] || continue
    if [[ "${_name}" == ".dotfiles-sync.yml" ]]; then
        MANIFEST="${_candidate}"
        break
    fi
    grep -q '^version:' "${_candidate}" && { MANIFEST="${_candidate}"; break; }
done

if [[ -n "${MANIFEST}" ]]; then
    ok "manifest found ($(basename "${MANIFEST}"))"
else
    fail "no manifest found (checked ${_MANIFEST_CANDIDATES})"
fi

for key in version core_api register deploy hooks; do
    if [[ -n "${MANIFEST}" ]] && grep -q "^${key}:" "${MANIFEST}"; then
        ok "manifest declares '${key}:'"
    else
        fail "manifest missing '${key}:'"
    fi
done

# Every deploy[].src and register.shell[].src/register.installers[].src
# referenced in the manifest must exist on disk.
_missing=0
if [[ -n "${MANIFEST}" ]]; then
    while IFS= read -r src; do
        [[ -z "${src}" ]] && continue
        if [[ -f "${REPO_ROOT}/${src}" ]]; then
            ok "referenced file exists: ${src}"
        else
            fail "manifest references missing file: ${src}"
            _missing=$((_missing + 1))
        fi
    done < <(grep -E '^[[:space:]]*(-[[:space:]]*)?src:' "${MANIFEST}" | sed -E 's/^[[:space:]]*-?[[:space:]]*src:[[:space:]]*//')
fi

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
