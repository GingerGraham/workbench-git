#!/usr/bin/env bash
# tests/check-include-values.sh — workbench-git
# Plain bash, numbered OK:/FAIL: checks, matching workbench-core's
# tests/check-*.sh convention (no framework).
#
# context, provider and projects_base are written into the gitdir: pattern of
# every section in ~/.config/git/project-includes, and context and provider
# also become directory and profile file names. A * ? [ ] or \ changes which
# directories a pattern matches; a quote or newline ends the value and can
# add config of its own. They are checked before anything is written:
#   - git-add-project refuses a bad context, provider or projects_base
#     before it creates anything;
#   - _git_regenerate_includes skips a project with a bad context or
#     provider (a hand-edited manifest) and writes the rest, and refuses to
#     touch the file at all when projects_base is bad;
#   - git-sync-projects skips such a project too, so it creates no
#     directory or profile for it.
# Names with spaces keep working.
#
# The validator checks need only git. The rest need mikefarah yq v4 (the
# manifest is real) and are skipped, loudly, where it is not installed. Set
# WB_TEST_YQ to point at one that is not on PATH.
#
# SC2015: '[[ cond ]] && ok || fail' is this suite's assertion idiom.
# SC2016: the snippets handed to run_driver are single-quoted on purpose, so
# the shell under test expands $HOME, not this one.
# shellcheck disable=SC2015,SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GIT_SH="${REPO_ROOT}/shell/git.sh"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

# Resolved with pwd -P: git matches a gitdir: pattern against the real path of
# the repository, and on macOS $TMPDIR is under /var, a symlink to /private/var.
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${WORK}"' EXIT

# ── mikefarah yq v4, if there is one ────────────────────────────────────────
YQ_DIR="${WORK}/yq-bin"
mkdir -p "${YQ_DIR}"
YQ_FOUND=""
for candidate in "${WB_TEST_YQ:-}" "$(command -v yq 2>/dev/null)"; do
    [[ -n "${candidate}" && -x "${candidate}" ]] || continue
    if "${candidate}" --version 2>&1 | grep -q 'mikefarah'; then
        YQ_FOUND="${candidate}"
        ln -s "${candidate}" "${YQ_DIR}/yq"
        break
    fi
done

# Driver, sourced by whichever shell is under test: core's helpers stubbed,
# shell/git.sh sourced, then the snippet in "$1" run.
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
eval "$1"
DRIVER

HOME_DIR="${WORK}/home"
CONFIG_DIR="${HOME_DIR}/.config/git"
MANIFEST="${CONFIG_DIR}/projects.yml"
INCLUDES="${CONFIG_DIR}/project-includes"

# run_driver <shell> <snippet> [manifest-content]
# Fresh HOME (with a ~/.gitconfig that includes project-includes) and cwd per
# run, and the manifest written first when one is given; output in
# ${WORK}/out.log.
run_driver() {
    local sh="$1" snippet="$2" manifest_content="${3:-}"
    rm -rf "${WORK:?}/home" "${WORK:?}/cwd"
    mkdir -p "${CONFIG_DIR}" "${WORK}/cwd"
    printf '[include]\n    path = ~/.config/git/project-includes\n' > "${HOME_DIR}/.gitconfig"
    [[ -z "${manifest_content}" ]] || printf '%s\n' "${manifest_content}" > "${MANIFEST}"
    # shellcheck disable=SC2016  # $0/$@ are for the inner shell, deliberately unexpanded
    (cd "${WORK}/cwd" && env -i HOME="${HOME_DIR}" PATH="${YQ_DIR}:${PATH}" \
        GIT_CONFIG_NOSYSTEM=1 GIT_SH="${GIT_SH}" \
        "${sh}" -c '. "$0" "$@"' "${WORK}/driver.sh" "${snippet}") >"${WORK}/out.log" 2>&1
}
show() { echo "--- output:"; cat "${WORK}/out.log"; echo "--- includes:"; cat "${INCLUDES}" 2>/dev/null; }

# Manifests. YAML double quotes turn \" and \n into a real quote and newline.
MANIFEST_MIXED='projects_base: ~/Projects
projects:
  - context: Personal
    provider: GitHub
    email: me@example.com
  - context: "bad\"ctx"
    provider: GitHub
    email: x@example.com
  - context: "x\"]\n[core]\n    sshCommand = evil"
    provider: GitHub
    email: x@example.com
  - context: "*"
    provider: GitHub
    email: x@example.com
  - context: Personal
    provider: "Git[Hub"
    email: x@example.com
  - context: Work Co
    provider: Azure DevOps
    email: w@example.com'

MANIFEST_BAD_BASE='projects_base: "~/Pro*jects"
projects:
  - context: Personal
    provider: GitHub
    email: me@example.com'

MANIFEST_ESCAPE='projects_base: ~/Projects
projects:
  - context: ../escape
    provider: GitHub
    email: x@example.com
  - context: Personal
    provider: GitHub
    email: me@example.com'

run_suite() { # <shell>
    local sh_name="$1" sh
    sh="$(command -v "${sh_name}" 2>/dev/null)"
    [[ -n "${sh}" ]] || { echo "SKIP: ${sh_name} not installed — include value checks not run under it"; return 0; }

    # ── 1. names: letters, digits, space . _ - ; not starting with - or . ────
    run_driver "${sh}" '
        for n in Personal "Acme Corp" a.b_c-d x1 "Azure DevOps" A-1; do
            _git_name_ok context "${n}" >/dev/null 2>&1 && echo "OKNAME" || echo "WRONGLY-REFUSED ${n}"
        done
        for n in "" -x .hidden .. . a/b "a\"b" "a*b" "a?b" "a[b" "a]b" "a\\b" "a${HOME}b" "a\$b" "a;b" "a'"'"'b" "a\`b" "é" "$(printf "a\tb")" "$(printf "a\nb")"; do
            if _git_name_ok context "${n}" >/dev/null 2>&1; then echo "WRONGLY-ACCEPTED $(printf "%q" "${n}")"; else echo "REFUSED"; fi
        done'
    # "a${HOME}b" is a valid path-ish string with '/', so it must be refused too
    if [[ "$(grep -c '^OKNAME$' "${WORK}/out.log")" -eq 6 && "$(grep -c '^REFUSED$' "${WORK}/out.log")" -eq 20 \
        && "$(grep -c '^WRONGLY' "${WORK}/out.log")" -eq 0 ]]; then
        ok "[${sh_name}] names: 6 valid ones pass (spaces included); empty, a leading - or ., '..', '/', quotes, glob characters, backslash, \$ ; backtick, non-ASCII, tab and newline are refused"
    else
        fail "[${sh_name}] _git_name_ok accepted or refused the wrong names"; show
    fi

    run_driver "${sh}" '_git_name_ok provider "a*b"; echo "RC $?"'
    grep -q '^ERROR provider a\\\*b may only use' "${WORK}/out.log" && grep -qx 'RC 1' "${WORK}/out.log" \
        && ok "[${sh_name}] the error names the field and shows the value escaped" \
        || { fail "[${sh_name}] the error does not name the field and value"; show; }

    # ── 2. projects_base ────────────────────────────────────────────────────
    run_driver "${sh}" '
        for b in /home/u/Projects "/home/u/My Projects" /srv/a.b-c_d; do
            _git_projects_base_ok "${b}" >/dev/null 2>&1 && echo "OKBASE" || echo "WRONGLY-REFUSED ${b}"
        done
        for b in "" "/p\"q" "/p\\q" "/p*q" "/p?q" "/p[q" "/p]q" "$(printf "/p\tq")" "$(printf "/p\nq")"; do
            if _git_projects_base_ok "${b}" >/dev/null 2>&1; then echo "WRONGLY-ACCEPTED $(printf "%q" "${b}")"; else echo "REFUSED"; fi
        done'
    if [[ "$(grep -c '^OKBASE$' "${WORK}/out.log")" -eq 3 && "$(grep -c '^REFUSED$' "${WORK}/out.log")" -eq 9 \
        && "$(grep -c '^WRONGLY' "${WORK}/out.log")" -eq 0 ]]; then
        ok "[${sh_name}] projects_base: plain paths and a space pass; empty, quote, backslash, * ? [ ], tab and newline are refused"
    else
        fail "[${sh_name}] _git_projects_base_ok accepted or refused the wrong paths"; show
    fi

    # ── 3. command level (needs mikefarah yq v4) ─────────────────────────────
    if [[ -z "${YQ_FOUND}" ]]; then
        echo "SKIP: mikefarah yq v4 not found — command-level include checks not run (set WB_TEST_YQ)"
        return 0
    fi

    # regenerate skips bad projects and writes the rest
    run_driver "${sh}" '_git_regenerate_includes; echo "RC $?"' "${MANIFEST_MIXED}"
    if grep -qx 'RC 0' "${WORK}/out.log" \
        && [[ "$(grep -c '^\[includeIf' "${INCLUDES}")" -eq 2 ]] \
        && grep -qxF "[includeIf \"gitdir:${HOME_DIR}/Projects/Personal/GitHub/\"]" "${INCLUDES}" \
        && grep -qxF "[includeIf \"gitdir:${HOME_DIR}/Projects/Work Co/Azure DevOps/\"]" "${INCLUDES}"; then
        ok "[${sh_name}] regenerate writes the two valid projects (one with spaces) and skips the four bad ones"
    else
        fail "[${sh_name}] regenerate wrote the wrong sections"; show
    fi
    [[ "$(grep -c '^WARN Skipping projects\[' "${WORK}/out.log")" -eq 4 ]] && grep -q '^WARN 4 project(s) left out' "${WORK}/out.log" \
        && ok "[${sh_name}] ...warning once per skipped project, and once with the count" \
        || { fail "[${sh_name}] the skipped projects were not each warned about"; show; }
    if ! grep -q 'evil' "${INCLUDES}" \
        && [[ "$(env -i HOME="${HOME_DIR}" PATH="${PATH}" GIT_CONFIG_NOSYSTEM=1 git config --file "${INCLUDES}" --get-regexp '^includeif\.' | wc -l | tr -d ' ')" -eq 2 ]] \
        && ! env -i HOME="${HOME_DIR}" PATH="${PATH}" GIT_CONFIG_NOSYSTEM=1 git config --file "${INCLUDES}" --get core.sshcommand >/dev/null 2>&1; then
        ok "[${sh_name}] a context carrying a quote and a newline cannot add config of its own: git reads the file as two include paths"
    else
        fail "[${sh_name}] injected text reached project-includes, or git cannot parse it"; show
    fi

    # a bad projects_base leaves the existing file alone
    run_driver "${sh}" 'printf "# old\n" > "${HOME}/.config/git/project-includes"; _git_regenerate_includes; echo "RC $?"' "${MANIFEST_BAD_BASE}"
    if grep -qx 'RC 1' "${WORK}/out.log" && grep -q '^ERROR projects_base' "${WORK}/out.log" \
        && [[ "$(cat "${INCLUDES}")" == "# old" ]]; then
        ok "[${sh_name}] a bad projects_base fails regenerate and leaves the existing file as it was"
    else
        fail "[${sh_name}] a bad projects_base did not fail cleanly"; show
    fi

    # git-add-project refuses bad input before creating anything
    local what args
    for what in "context a/b" "context a*b" "context ..x" "provider Git*Hub" "provider -x"; do
        args="${what#* }"
        case "${what%% *}" in
            context)  run_driver "${sh}" "git-add-project '${args}' GitHub me@example.com --no-cli; echo \"RC \$?\"" ;;
            provider) run_driver "${sh}" "git-add-project Personal '${args}' me@example.com --no-cli; echo \"RC \$?\"" ;;
        esac
        if grep -qx 'RC 1' "${WORK}/out.log" && grep -q '^ERROR ' "${WORK}/out.log" \
            && [[ ! -e "${MANIFEST}" && ! -e "${INCLUDES}" && ! -d "${HOME_DIR}/Projects" ]]; then
            ok "[${sh_name}] git-add-project refuses ${what%% *} '${args}' and creates nothing"
        else
            fail "[${sh_name}] git-add-project did not refuse ${what%% *} '${args}' cleanly"; show
        fi
    done

    run_driver "${sh}" 'git-add-project Personal GitHub me@example.com --no-cli; echo "RC $?"' "${MANIFEST_BAD_BASE}"
    if grep -qx 'RC 1' "${WORK}/out.log" && grep -q '^ERROR projects_base' "${WORK}/out.log" \
        && [[ ! -d "${HOME_DIR}/Pro*jects" && ! -e "${CONFIG_DIR}/profiles" ]] \
        && [[ "$("${YQ_FOUND}" '.projects | length' "${MANIFEST}")" -eq 1 ]]; then
        ok "[${sh_name}] git-add-project with a bad projects_base stops before creating a directory, profile or entry"
    else
        fail "[${sh_name}] git-add-project went ahead with a bad projects_base"; show
    fi

    # names with spaces still work, end to end
    run_driver "${sh}" 'git-add-project "Acme Corp" "Azure DevOps" me@acme.example --no-cli; echo "RC $?"; git init -q "${HOME}/Projects/Acme Corp/Azure DevOps/repo"'
    if grep -qx 'RC 0' "${WORK}/out.log" \
        && grep -qxF "[includeIf \"gitdir:${HOME_DIR}/Projects/Acme Corp/Azure DevOps/\"]" "${INCLUDES}" \
        && [[ -f "${CONFIG_DIR}/profiles/acme-corp-azure-devops.inc" ]] \
        && [[ "$(env -i HOME="${HOME_DIR}" PATH="${PATH}" GIT_CONFIG_NOSYSTEM=1 git -C "${HOME_DIR}/Projects/Acme Corp/Azure DevOps/repo" config --get user.email)" == "me@acme.example" ]]; then
        ok "[${sh_name}] names with spaces still work: includeIf section, profile, and git resolves the identity in the project"
    else
        fail "[${sh_name}] a project with spaces in its names no longer works"; show
    fi

    # sync skips a bad entry without creating anything for it
    run_driver "${sh}" 'git-sync-projects; echo "RC $?"' "${MANIFEST_ESCAPE}"
    if grep -qx 'RC 0' "${WORK}/out.log" \
        && [[ ! -e "${HOME_DIR}/escape" && ! -e "${CONFIG_DIR}/profiles/..-escape-github.inc" ]] \
        && [[ -d "${HOME_DIR}/Projects/Personal/GitHub" && -f "${CONFIG_DIR}/profiles/personal-github.inc" ]] \
        && [[ "$(grep -c '^\[includeIf' "${INCLUDES}")" -eq 1 ]] \
        && grep -q '^WARN Skipping projects\[0\]' "${WORK}/out.log"; then
        ok "[${sh_name}] git-sync-projects skips a '../escape' context: no directory or profile for it, the other project is synced"
    else
        fail "[${sh_name}] git-sync-projects acted on an unsafe context"; show
    fi

    run_driver "${sh}" 'git-sync-projects; echo "RC $?"' "${MANIFEST_BAD_BASE}"
    if grep -qx 'RC 1' "${WORK}/out.log" && [[ ! -d "${HOME_DIR}/Pro*jects" && ! -e "${CONFIG_DIR}/profiles" && ! -e "${INCLUDES}" ]]; then
        ok "[${sh_name}] git-sync-projects with a bad projects_base stops before creating anything"
    else
        fail "[${sh_name}] git-sync-projects went ahead with a bad projects_base"; show
    fi
}

run_suite bash
run_suite zsh

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
[[ "${FAILED}" -eq 0 ]]
