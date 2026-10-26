#!/usr/bin/env bash
# tests/check-yq-availability.sh — workbench-git
# Proves the project-management functions' availability declaration in
# shell/git.sh (_wb_alias_availability --needs/--install, workbench-core
# D86) against core's real listing code: without a working mikefarah/yq v4
# the seven functions leave the main list of get-git-functions (the getter
# core generates from register.getters[], workbench-core D89) and appear
# under one "yq v4 (mikefarah/yq)" header with the install command; with
# v4 they are listed normally; they stay callable either way; and the check
# is not cached, so installing yq and rerunning works in the same shell.
#
# Needs WB, MODULE_NAME, MODULE_URL, MODULE_BRANCH and MODULE_ROOT, set by
# workbench-core's module CI ("add to core", step 8). That step runs only
# tests/check-add-to-core.sh, which calls this suite at its end.
#
# SC2015: '[[ cond ]] && ok || fail' is this suite's assertion idiom.
# shellcheck disable=SC2015
set -uo pipefail

# Module CI's structural-tests job also runs every tests/check-*.sh on its
# own, without a core checkout: nothing to list against there.
if [[ -z "${WB:-}" || -z "${MODULE_NAME:-}" || -z "${MODULE_URL:-}" || -z "${MODULE_BRANCH:-}" || -z "${MODULE_ROOT:-}" ]]; then
    echo "SKIP: needs WB, MODULE_NAME, MODULE_URL, MODULE_BRANCH and MODULE_ROOT — run by workbench-core's module CI ('add to core', step 8)"
    exit 0
fi

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
export HOME="${WORK}/home"
export XDG_CONFIG_HOME="${HOME}/.config"
export XDG_DATA_HOME="${HOME}/.local/share"
export GIT_CONFIG_NOSYSTEM=1
mkdir -p "${HOME}"

# <core>/bin/wb -> <core>
CORE="$(cd "$(dirname "${WB}")/.." && pwd)"
GIT_SH="${MODULE_ROOT}/shell/git.sh"

# The getter's label, as core prints it, comes from the manifest.
# shellcheck source=/dev/null
source "${CORE}/lib/manifest/parse.sh"
MANIFEST="$(workbench_resolve_manifest_path "${MODULE_ROOT}")"
LABEL="$(workbench_manifest_register_getter_entries "${MANIFEST}" \
    | awk -F'|' '$2 == "get-git-functions" { print $3; exit }')"
if [[ -n "${LABEL}" ]]; then
    ok "manifest declares get-git-functions with label '${LABEL}'"
else
    fail "no register.getters[] entry for get-git-functions in ${MANIFEST}"
fi
MAIN_TITLE="[INFO] ${LABEL} — functions:"

GATED="git-add-project git-add-project-cli git-list-projects git-remove-project git-remove-project-cli git-sync-projects git-update-project"
UNGATED="git-setup-identity gwt gwt-cd"
BLOCK_TITLE="[INFO] ${LABEL} — functions — available once tooling is installed:"
NEEDS_HEADER="  yq v4 (mikefarah/yq)"
INSTALL_HEADER="${NEEDS_HEADER} — install: wb tools install yq"

# ── register the module, so core renders its installers.list ─────────────────
run() { "$@" >"${WORK}/out.log" 2>&1 || { echo "--- $* failed:"; cat "${WORK}/out.log"; return 1; }; }
run "${WB}" add "${MODULE_NAME}" "${MODULE_URL}" </dev/null || fail "wb add"
run "${WB}" track "${MODULE_NAME}" --branch "${MODULE_BRANCH}" </dev/null || fail "wb track"
run "${WB}" update "${MODULE_NAME}" </dev/null || fail "wb update"

INSTALLERS_LIST="${XDG_DATA_HOME}/workbench/modules/${MODULE_NAME}/installers.list"
grep -q '|yq$' "${INSTALLERS_LIST}" 2>/dev/null \
    && ok "wb update rendered installers.list with a yq installer" \
    || fail "no yq line in ${INSTALLERS_LIST}"

# ── a PATH with exactly the tools a getter call needs, and no yq ─────────────
# Don't rely on the runner lacking yq (module CI puts mikefarah/yq on PATH).
# sleep/kill: core's predicate-timeout watchdog. column: the name lists.
# uname: core's functions.sh detects the platform when sourced.
BARE_BIN="${WORK}/bin"
mkdir -p "${BARE_BIN}"
for tool in awk basename bash cat column cut dirname env grep head kill mkdir mktemp rm sed sleep sort tr uname uniq wc; do
    tool_path="$(command -v "${tool}" 2>/dev/null)"
    if [[ -z "${tool_path}" ]]; then
        fail "'${tool}' is not on this runner's PATH (column: Debian/Ubuntu package bsdextrautils)"
        continue
    fi
    ln -s "${tool_path}" "${BARE_BIN}/${tool}"
done

make_yq_stub() {
    local dir="$1" version_line="$2"
    mkdir -p "${dir}"
    printf '#!%s\necho %q\n' "${BASH}" "${version_line}" > "${dir}/yq"
    chmod +x "${dir}/yq"
}
WRONG_BIN="${WORK}/yq-wrong"
V4_BIN="${WORK}/yq-v4"
make_yq_stub "${WRONG_BIN}" "yq 3.2.3"
make_yq_stub "${V4_BIN}" "yq (https://github.com/mikefarah/yq/) version v4.44.1"

PATH_MISSING="${BARE_BIN}"
PATH_WRONG="${WRONG_BIN}:${BARE_BIN}"
PATH_V4="${V4_BIN}:${BARE_BIN}"

# shell_with <path> <command...>: a fresh subshell with core's function
# library and shell/git.sh sourced the way the interactive loader does, the
# getter defined the way the loader defines it (lib/loader.sh, D89), then
# <command...>. Output (stdout and stderr) goes to ${WORK}/getter.log.
shell_with() {
    local path="$1"; shift
    (
        PATH="${path}"
        # shellcheck source=/dev/null
        source "${CORE}/lib/core/log.sh"
        # shellcheck source=/dev/null
        source "${CORE}/lib/core/functions.sh"
        # shellcheck source=/dev/null
        source "${GIT_SH}"
        eval "get-git-functions() { _wb_module_getter '${MODULE_NAME}' get-git-functions; }"
        "$@"
    ) >"${WORK}/getter.log" 2>&1
}

# The main functions list and the block below it, one name or header per
# line. Both end at the first blank line.
main_names() {
    awk -v t="${MAIN_TITLE}" '$0 == t { f = 1; next } f && /^$/ { exit } f' "$1" \
        | tr -s ' \t' '\n' | grep -v '^$'
}
block_lines() {
    awk -v t="${BLOCK_TITLE}" '$0 == t { f = 1; next } f && /^$/ { exit } f' "$1"
}
block_names() {
    block_lines "$1" | grep '^    ' | tr -s ' \t' '\n' | grep -v '^$'
}
has_block() { grep -qxF "${BLOCK_TITLE}" "$1"; }

# names_in <list-fn> <log> <names...>: 0 if every name is in the list.
names_in() {
    local fn="$1" log="$2" name; shift 2
    for name in "$@"; do
        "${fn}" "${log}" | grep -qxF "${name}" || return 1
    done
}
names_absent() {
    local fn="$1" log="$2" name; shift 2
    for name in "$@"; do
        "${fn}" "${log}" | grep -qxF "${name}" && return 1
    done
    return 0
}
show() { echo "--- get-git-functions output:"; cat "$1"; }

LOG="${WORK}/getter.log"

# shellcheck disable=SC2086  # GATED/UNGATED are word lists by design
{
# ── 1. yq missing ────────────────────────────────────────────────────────────
if PATH="${PATH_MISSING}" command -v yq >/dev/null 2>&1; then
    fail "yq is still found on the bare PATH — the 'missing' cases would prove nothing"
else
    ok "no yq on the bare PATH"
fi

shell_with "${PATH_MISSING}" get-git-functions
names_absent main_names "${LOG}" ${GATED} \
    && ok "yq missing: the seven project functions are not in the main list" \
    || { fail "yq missing: a project function is still in the main list"; show "${LOG}"; }
names_in main_names "${LOG}" ${UNGATED} \
    && ok "yq missing: git-setup-identity, gwt, gwt-cd are in the main list" \
    || { fail "yq missing: an ungated function is missing from the main list"; show "${LOG}"; }
names_in block_names "${LOG}" ${GATED} \
    && ok "yq missing: all seven are in the 'available once tooling is installed' block" \
    || { fail "yq missing: the block does not name all seven"; show "${LOG}"; }

# ── 2. install hint, with and without an installer ───────────────────────────
headers="$(block_lines "${LOG}" | grep -v '^    ')"
[[ "${headers}" == "${INSTALL_HEADER}" ]] \
    && ok "one header, ending '— install: wb tools install yq'" \
    || { fail "block header is '${headers}'"; show "${LOG}"; }

mv "${INSTALLERS_LIST}" "${INSTALLERS_LIST}.aside"
shell_with "${PATH_MISSING}" get-git-functions
headers="$(block_lines "${LOG}" | grep -v '^    ')"
[[ "${headers}" == "${NEEDS_HEADER}" ]] \
    && ok "no installers.list: header is exactly '${NEEDS_HEADER}', no install suffix" \
    || { fail "no installers.list: header is '${headers}'"; show "${LOG}"; }
mv "${INSTALLERS_LIST}.aside" "${INSTALLERS_LIST}"

# ── 3. wrong variant ─────────────────────────────────────────────────────────
shell_with "${PATH_WRONG}" get-git-functions
names_absent main_names "${LOG}" ${GATED} && names_in block_names "${LOG}" ${GATED} \
    && ok "yq 3.2.3: the seven are in the block, not the main list" \
    || { fail "yq 3.2.3: the seven are not all in the block"; show "${LOG}"; }

# ── 4. mikefarah/yq v4 ───────────────────────────────────────────────────────
shell_with "${PATH_V4}" get-git-functions
names_in main_names "${LOG}" ${GATED} && ! has_block "${LOG}" \
    && ok "yq v4: all seven in the main list, no block" \
    || { fail "yq v4: not all listed, or a block is printed"; show "${LOG}"; }

# ── 5. fix and rerun in one shell ────────────────────────────────────────────
fix_and_rerun() {
    get-git-functions > "${WORK}/before.log"
    PATH="${PATH_V4}"
    get-git-functions > "${WORK}/after.log"
}
shell_with "${PATH_MISSING}" fix_and_rerun
names_in block_names "${WORK}/before.log" ${GATED} \
    && names_in main_names "${WORK}/after.log" ${GATED} && ! has_block "${WORK}/after.log" \
    && ok "same shell: block while yq is missing, all listed once yq v4 is on PATH" \
    || { fail "same shell: the listing did not follow yq appearing"; show "${WORK}/before.log"; show "${WORK}/after.log"; }

# ── 6. still callable ────────────────────────────────────────────────────────
if shell_with "${PATH_WRONG}" git-list-projects; then
    fail "yq 3.2.3: git-list-projects returned 0"
else
    grep -q "Wrong yq detected" "${LOG}" \
        && ok "yq 3.2.3: git-list-projects runs, fails, and prints 'Wrong yq detected'" \
        || { fail "yq 3.2.3: git-list-projects failed without 'Wrong yq detected'"; cat "${LOG}"; }
fi
if shell_with "${PATH_MISSING}" git-list-projects; then
    fail "yq missing: git-list-projects returned 0"
else
    grep -q "yq is required" "${LOG}" \
        && ok "yq missing: git-list-projects runs, fails, and prints 'yq is required'" \
        || { fail "yq missing: git-list-projects failed without 'yq is required'"; cat "${LOG}"; }
fi

# ── 7. WORKBENCH_FUNCTIONS_SHOW_ALL ──────────────────────────────────────────
show_all() { WORKBENCH_FUNCTIONS_SHOW_ALL=true get-git-functions; }
shell_with "${PATH_MISSING}" show_all
names_in main_names "${LOG}" ${GATED} && ! has_block "${LOG}" \
    && ok "SHOW_ALL=true, yq missing: all seven in the main list, no block" \
    || { fail "SHOW_ALL=true: not all listed, or a block is printed"; show "${LOG}"; }
}

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
[[ "${FAILED}" -eq 0 ]]
