#!/usr/bin/env bash
# tests/check-envrc-allow.sh — workbench-git
# Plain bash, numbered OK:/FAIL: checks, matching workbench-core's
# tests/check-*.sh convention (no framework).
#
# The generated .envrc is allowed as soon as workbench-git writes it
# (_git_allow_envrc): without that, direnv blocks it, GH_CONFIG_DIR is never
# set, and `gh auth login` in the project stores credentials in the default
# ~/.config/gh instead of the context's. Because the file is now trusted
# automatically, the values written into it are validated first
# (_git_envrc_values_ok). This suite proves both, under bash and, when
# installed, zsh (every register.shell file is also sourced into zsh).
#
# Standalone: core's helpers are stubbed, direnv and yq are stubs on a PATH
# built for the test, and nothing touches the network.
#
# SC2015: '[[ cond ]] && ok || fail' is this suite's assertion idiom.
# shellcheck disable=SC2015
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GIT_SH="${REPO_ROOT}/shell/git.sh"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# ── a PATH with only what the wiring needs, and stub direnv/yq ──────────────
# The runner may have a real direnv; a bare PATH makes "not installed" real.
BARE_BIN="${WORK}/bin"
mkdir -p "${BARE_BIN}"
for tool in cat chmod dirname grep head ls mkdir rm tr; do
    tool_path="$(command -v "${tool}" 2>/dev/null)"
    if [[ -z "${tool_path}" ]]; then
        fail "'${tool}' is not on this runner's PATH"
        continue
    fi
    ln -s "${tool_path}" "${BARE_BIN}/${tool}"
done

# yq as tests/check-yq-availability.sh stubs it: v4 by its version line. No
# manifest exists here, so nothing else should ever ask it anything.
STUB_BIN="${WORK}/stub-bin"
mkdir -p "${STUB_BIN}"
cat > "${STUB_BIN}/yq" <<EOF
#!${BASH}
[[ "\$1" == "--version" ]] && { echo "yq (https://github.com/mikefarah/yq/) version v4.44.1"; exit 0; }
echo "unexpected yq call: \$*" >&2; exit 1
EOF
cat > "${STUB_BIN}/direnv" <<EOF
#!${BASH}
printf '%s\n' "\$*" >> "\${DIRENV_LOG}"
EOF
chmod +x "${STUB_BIN}/yq" "${STUB_BIN}/direnv"
YQ_ONLY_BIN="${WORK}/yq-only"
mkdir -p "${YQ_ONLY_BIN}"
ln -s "${STUB_BIN}/yq" "${YQ_ONLY_BIN}/yq"

# Driver, sourced by whichever shell is under test: core's helpers stubbed,
# shell/git.sh sourced, then one scenario. "$1" = scenario.
cat > "${WORK}/driver.sh" <<'DRIVER'
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
# shellcheck disable=SC1090
. "${GIT_SH}"
case "$1" in
    wire)
        mkdir -p "${HOME}/Projects/Personal/GitHub"
        _git_wire_project_cli Personal GitHub gh </dev/null
        echo "RC $?"
        ;;
    wire-twice)
        mkdir -p "${HOME}/Projects/Personal/GitHub"
        _git_wire_project_cli Personal GitHub gh </dev/null
        _git_wire_project_cli Personal GitHub gh </dev/null
        echo "RC $?"
        ;;
    bad-context)
        mkdir -p "${HOME}/Projects/a\$(touch x)/GitHub"
        _git_write_envrc 'a$(touch x)' GitHub gh ""
        echo "RC $?"
        ;;
    bad-cli)
        mkdir -p "${HOME}/Projects/Personal/GitHub"
        _git_write_envrc Personal GitHub foo ""
        echo "RC $?"
        ;;
    bad-host)
        mkdir -p "${HOME}/Projects/Personal/GitHub"
        _git_write_envrc Personal GitHub gh 'x;y'
        echo "RC $?"
        ;;
esac
DRIVER

# run_driver <shell> <scenario> <with-direnv: yes|no>
# Fresh HOME and cwd per run; output in ${WORK}/out.log.
run_driver() {
    local sh="$1" scenario="$2" with_direnv="$3" path
    rm -rf "${WORK:?}/home" "${WORK:?}/cwd" "${WORK:?}/direnv.log"
    mkdir -p "${WORK}/home" "${WORK}/cwd"
    : > "${WORK}/direnv.log"
    if [[ "${with_direnv}" == "yes" ]]; then
        path="${STUB_BIN}:${BARE_BIN}"
    else
        path="${YQ_ONLY_BIN}:${BARE_BIN}"
    fi
    # shellcheck disable=SC2016  # $0/$@ are for the inner shell, deliberately unexpanded
    (cd "${WORK}/cwd" && env -i HOME="${WORK}/home" PATH="${path}" \
        GIT_SH="${GIT_SH}" DIRENV_LOG="${WORK}/direnv.log" \
        "${sh}" -c '. "$0" "$@"' "${WORK}/driver.sh" "${scenario}") >"${WORK}/out.log" 2>&1
}
show() { echo "--- output:"; cat "${WORK}/out.log"; echo "--- direnv calls:"; cat "${WORK}/direnv.log"; }

ENVRC="${WORK}/home/Projects/Personal/GitHub/.envrc"

run_suite() { # <shell>
    local sh_name="$1" sh
    sh="$(command -v "${sh_name}" 2>/dev/null)"
    [[ -n "${sh}" ]] || { echo "SKIP: ${sh_name} not installed — .envrc checks not run under it"; return 0; }

    # ── 1. wiring writes the .envrc and allows it ───────────────────────────
    run_driver "${sh}" wire yes
    [[ -f "${ENVRC}" ]] && grep -qx 'use git_context gh personal' "${ENVRC}" \
        && ok "[${sh_name}] wiring a context writes the .envrc" \
        || { fail "[${sh_name}] no .envrc with 'use git_context gh personal'"; show; }
    [[ "$(cat "${WORK}/direnv.log")" == "allow ${ENVRC}" ]] \
        && ok "[${sh_name}] ...and runs 'direnv allow <path>' once" \
        || { fail "[${sh_name}] direnv was not called as 'allow ${ENVRC}'"; show; }

    # ── 2. nothing changed: allowed again ───────────────────────────────────
    run_driver "${sh}" wire-twice yes
    [[ "$(grep -c "^allow ${ENVRC}\$" "${WORK}/direnv.log")" -eq 2 && "$(wc -l < "${WORK}/direnv.log" | tr -d ' ')" -eq 2 ]] \
        && ok "[${sh_name}] a second run with nothing changed allows it again" \
        || { fail "[${sh_name}] expected two 'direnv allow' calls"; show; }

    # ── 3. no direnv: written, warned, returns 0 ────────────────────────────
    run_driver "${sh}" wire no
    [[ -f "${ENVRC}" ]] \
        && ok "[${sh_name}] without direnv the .envrc is still written" \
        || { fail "[${sh_name}] without direnv no .envrc was written"; show; }
    grep -q "^WARN .*direnv allow ${ENVRC}\$" "${WORK}/out.log" \
        && ok "[${sh_name}] ...the warning names 'direnv allow <path>'" \
        || { fail "[${sh_name}] no warning naming 'direnv allow ${ENVRC}'"; show; }
    grep -qx 'RC 0' "${WORK}/out.log" \
        && ok "[${sh_name}] ...and the wiring returns 0" \
        || { fail "[${sh_name}] wiring without direnv did not return 0"; show; }

    # ── 4. values that could carry shell syntax are refused ─────────────────
    local scenario envrc what
    for scenario in bad-context bad-cli bad-host; do
        case "${scenario}" in
            bad-context) what="context 'a\$(touch x)'"; envrc="${WORK}/home/Projects/a\$(touch x)/GitHub/.envrc" ;;
            bad-cli)     what="CLI 'foo'";              envrc="${ENVRC}" ;;
            bad-host)    what="host 'x;y'";             envrc="${ENVRC}" ;;
        esac
        run_driver "${sh}" "${scenario}" yes
        if grep -qx 'RC 1' "${WORK}/out.log" && grep -q '^ERROR ' "${WORK}/out.log" \
            && [[ ! -e "${envrc}" && ! -s "${WORK}/direnv.log" && ! -e "${WORK}/cwd/x" ]]; then
            ok "[${sh_name}] ${what} is refused: error, no .envrc, no direnv call"
        else
            fail "[${sh_name}] ${what} was not refused cleanly"; show
        fi
    done
}

run_suite bash
run_suite zsh

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
[[ "${FAILED}" -eq 0 ]]
