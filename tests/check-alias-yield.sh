#!/usr/bin/env bash
# tests/check-alias-yield.sh — workbench-git
# Plain bash, numbered OK:/FAIL: checks, matching workbench-core's
# tests/check-*.sh convention (no framework).
#
# workbench-core D124: workbench never replaces an alias or function it did
# not define. shell/git.sh defines every alias through workbench_alias_define,
# so a name the user's shell already uses is left alone.
#
# Proves, with the real shell/git.sh:
#   - with nothing in the way, every alias is defined exactly as before the
#     conversion (tests/fixtures/git-aliases.golden, captured from the
#     unconverted file);
#   - with a function `gd`, a function `gst` and a different alias `gcm`
#     already present, those three are untouched, every other alias is
#     defined, and three clashes are recorded (two function, one alias);
#   - the reported sequence: the host's file defining `gd() {` re-sourced
#     after workbench loaded raises no syntax error.
#
# The helper under test is core's own when a core checkout is found
# (WORKBENCH_CORE_DIR, or ../workbench-core next to this repo). Module CI
# runs this suite with only this repo checked out, so otherwise a small
# double stands in, written to the contract in core's contracts/core-api.md;
# core's own tests cover the real helper.
#
# Regenerate the golden file only on purpose, from the unconverted file:
#   WB_UPDATE_GOLDEN=1 GIT_SH=<path to the old shell/git.sh> bash tests/check-alias-yield.sh
#
# Runs under bash and, when installed, zsh.
#
# SC2015: '[[ cond ]] && ok || fail' is this suite's assertion idiom.
# shellcheck disable=SC2015
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GIT_SH="${GIT_SH:-${REPO_ROOT}/shell/git.sh}"
GOLDEN="${SCRIPT_DIR}/fixtures/git-aliases.golden"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }
skip() { echo "SKIP: $*"; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# ── Where does the helper come from? ────────────────────────────────────────
CORE_FUNCTIONS=""
for candidate in "${WORKBENCH_CORE_DIR:-}" "${REPO_ROOT}/../workbench-core"; do
    [[ -n "${candidate}" ]] || continue
    if [[ -f "${candidate}/lib/core/functions.sh" ]] \
        && grep -q '^workbench_alias_define()' "${candidate}/lib/core/functions.sh"; then
        CORE_FUNCTIONS="$(cd "${candidate}" && pwd)/lib/core"
        break
    fi
done

# The prelude every case starts with: core's helpers, real or stubbed, then
# the host's own definitions come from the case, then shell/git.sh.
if [[ -n "${CORE_FUNCTIONS}" ]]; then
    printf '%s\n' \
        "source '${CORE_FUNCTIONS}/log.sh' >/dev/null 2>&1" \
        "source '${CORE_FUNCTIONS}/functions.sh' >/dev/null 2>&1" > "${WORK}/prelude.sh"
    HELPER_SOURCE="core's real functions.sh"
else
    cat > "${WORK}/prelude.sh" <<'PRELUDE'
log_info()  { echo "INFO $*"; }
log_warn()  { echo "WARN $*"; }
log_error() { echo "ERROR $*"; }
log_debug() { :; }
_wb_alias_availability()   { :; }
_wb_declare_availability() { :; }
_wb_availability_needs()   { :; }
_wb_prompt_hook_registered() { return 1; }
_read_prompt() { :; }
_str_lower() { printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]'; }
WORKBENCH_ALIASES_OURS="${WORKBENCH_ALIASES_OURS:-}"
WORKBENCH_ALIAS_CLASHES="${WORKBENCH_ALIAS_CLASHES:-}"
# The contract in core's contracts/core-api.md, in the same words.
workbench_alias_define() {
    local name="$1" module="$2" value="$3" kind existing wanted
    case " ${WORKBENCH_ALIASES_OURS} " in
        *" ${name} "*) builtin alias "${name}=${value}"; return 0 ;;
    esac
    if builtin typeset -f "${name}" >/dev/null 2>&1; then
        kind="function"
    elif builtin alias "${name}" >/dev/null 2>&1; then
        existing="$(builtin alias "${name}")"
        wanted="$( builtin unalias "${name}"; builtin alias "${name}=${value}"; builtin alias "${name}" )"
        if [[ "${existing}" == "${wanted}" ]]; then
            WORKBENCH_ALIASES_OURS="${WORKBENCH_ALIASES_OURS} ${name}"
            return 0
        fi
        kind="alias"
    else
        builtin alias "${name}=${value}"
        WORKBENCH_ALIASES_OURS="${WORKBENCH_ALIASES_OURS} ${name}"
        return 0
    fi
    WORKBENCH_ALIAS_CLASHES="${WORKBENCH_ALIAS_CLASHES}${name}|${module}|${kind}|${value}
"
    return 1
}
PRELUDE
    HELPER_SOURCE="a test double of the contract (no core checkout found)"
fi
echo "NOTE: alias helper under test: ${HELPER_SOURCE}"

# A fake gh and the gh-copilot extension directory, so the two conditional
# aliases (copilot, upgrade-copilot) are in play too.
FAKE_HOME="${WORK}/home"
FAKE_BIN="${WORK}/bin"
mkdir -p "${FAKE_HOME}/.local/share/gh/extensions/gh-copilot" "${FAKE_BIN}"
printf '#!/bin/sh\nexit 0\n' > "${FAKE_BIN}/gh"
chmod +x "${FAKE_BIN}/gh"

# The host's own definitions: separate lines in a sourced file, the way a
# real profile defines them.
cat > "${WORK}/host-clashes.sh" <<'HOST'
gd() {
    echo "host gd function"
}
gst() { echo "host gst function"; }
alias gcm='git commit --signoff -m'
HOST
cat > "${WORK}/host-gd.sh" <<'HOST'
gd() {
    echo "host gd function"
}
HOST

# run_case <bash|zsh> <name> <body> — a clean shell: the prelude, the body
# (which sources shell/git.sh where it wants to). Output is the body's own.
run_case() {
    local shell="$1" name="$2" body="$3" script
    script="${WORK}/case-${name}-${shell}.sh"
    {
        [[ "${shell}" == "bash" ]] && echo "shopt -s expand_aliases"
        echo ". '${WORK}/prelude.sh'"
        printf '%s\n' "${body}"
    } > "${script}"
    env -i HOME="${FAKE_HOME}" PATH="${FAKE_BIN}:/usr/local/bin:/usr/bin:/bin" TERM=dumb \
        "${shell}" -f "${script}" 2>&1 </dev/null
}

# ALIAS_DUMP — this shell's aliases as sorted, unquoted `name=value` lines,
# the same text in bash and zsh. zsh leaves a value with no spaces unquoted
# and ships two aliases of its own (run-help, which-command), so the quotes
# are stripped and those two are left out.
ALIAS_DUMP='alias | sed -e "s/^alias //" -e "s/^\([^=]*\)=\x27\(.*\)\x27\$/\1=\2/" | grep -vE "^(run-help|which-command)=" | sort'

if [[ -n "${WB_UPDATE_GOLDEN:-}" ]]; then
    mkdir -p "$(dirname "${GOLDEN}")"
    run_case bash golden ". '${GIT_SH}' >/dev/null 2>&1; ${ALIAS_DUMP}" > "${GOLDEN}"
    echo "Wrote ${GOLDEN} ($(grep -c . "${GOLDEN}") aliases) from ${GIT_SH}"
    exit 0
fi

[[ -f "${GOLDEN}" ]] || { echo "FAIL: golden file missing: ${GOLDEN}"; exit 1; }

check_shell() {
    local shell="$1" out expected

    # 1. Nothing in the way: exactly the aliases and values of the old file.
    out="$(run_case "${shell}" plain ". '${GIT_SH}' >/dev/null 2>&1; ${ALIAS_DUMP}")"
    if [[ "${out}" == "$(cat "${GOLDEN}")" ]]; then
        ok "${shell}: no foreign state — all $(grep -c . "${GOLDEN}") aliases defined, same names and values as before the conversion"
    else
        fail "${shell}: aliases differ from the golden file (diff of expected vs got):"
        diff <(cat "${GOLDEN}") <(printf '%s\n' "${out}") | head -20
    fi

    # 2. A function gd, a function gst and a different alias gcm in the way.
    out="$(run_case "${shell}" clash ". '${WORK}/host-clashes.sh'; . '${GIT_SH}' >/dev/null 2>&1; ${ALIAS_DUMP}")"
    expected="$( { grep -vE '^(gd|gst|gcm)=' "${GOLDEN}"; echo "gcm=git commit --signoff -m"; } | sort )"
    if [[ "${out}" == "${expected}" ]]; then
        ok "${shell}: gd and gst (functions) and gcm (a different alias) are untouched; every other alias is defined"
    else
        fail "${shell}: aliases with three names taken are not as expected (expected vs got):"
        diff <(printf '%s\n' "${expected}") <(printf '%s\n' "${out}") | head -20
    fi

    out="$(run_case "${shell}" kinds ". '${WORK}/host-clashes.sh'; . '${GIT_SH}' >/dev/null 2>&1; printf '%s' \"\${WORKBENCH_ALIAS_CLASHES}\"")"
    if [[ "$(grep -c . <<<"${out}")" -eq 3 ]] \
        && grep -q '^gd|git|function|git diff$' <<<"${out}" \
        && grep -q '^gst|git|function|git status$' <<<"${out}" \
        && grep -q '^gcm|git|alias|git commit -m$' <<<"${out}"; then
        ok "${shell}: three clashes recorded — two function (gd, gst) and one alias (gcm), module 'git'"
    else
        fail "${shell}: clash records wrong"; printf '%s\n' "${out}"
    fi

    # 3. The reported sequence, against the real shell/git.sh: the host's
    #    gd() { file is sourced first (a fresh shell), workbench loads, then
    #    the host's file again, twice (bashsource).
    out="$(run_case "${shell}" resource ". '${WORK}/host-gd.sh'; . '${GIT_SH}' >/dev/null 2>&1; . '${WORK}/host-gd.sh'; echo R1=\$?; . '${WORK}/host-gd.sh'; echo R2=\$?; gd")"
    if grep -q '^R1=0$' <<<"${out}" && grep -q '^R2=0$' <<<"${out}" \
        && grep -q '^host gd function$' <<<"${out}" \
        && ! grep -qiE 'syntax error|parse error|defining function based on alias' <<<"${out}"; then
        ok "${shell}: re-sourcing the host's gd() { file twice after workbench-git loaded: no error, gd is still the host's function"
    else
        fail "${shell}: re-sourcing the host's file broke"; printf '%s\n' "${out}"
    fi
}

check_shell bash
if command -v zsh >/dev/null 2>&1; then
    check_shell zsh
else
    skip "zsh is not installed — zsh checks not run (CI installs zsh on ubuntu so it never skips there)"
fi

echo
if [[ "${FAILED}" -eq 0 ]]; then
    echo "All ${check_no} checks passed."
    exit 0
fi
echo "${FAILED} of ${check_no} checks failed."
exit 1
