#!/usr/bin/env bash
# tests/check-ssh-key.sh — workbench-git
# Plain bash, numbered OK:/FAIL: checks, matching workbench-core's
# tests/check-*.sh convention (no framework).
#
# A project's optional ssh_key is stored in projects.yml and written to its
# profile .inc as core.sshCommand, so git over SSH inside that project tree
# uses that key. This suite proves:
#   - the helpers: ~/ expansion, the path is quoted into core.sshCommand,
#     and any path that could break out of the quotes is refused;
#   - git-add-project --ssh-key and git-update-project --ssh-key (set, and
#     'none' to remove) change the manifest and the profile together;
#   - git-list-projects and git-sync-projects --status show the key, and
#     git-sync-projects writes it back into a recreated profile;
#   - git itself picks the key up inside the project tree, through the
#     includeIf section, and not outside it.
#
# The helper checks need only git. The command-level checks need mikefarah
# yq v4 (the manifest is real); they are skipped, loudly, where it is not
# installed. Set WB_TEST_YQ to point at one that is not on PATH.
#
# SC2015: '[[ cond ]] && ok || fail' is this suite's assertion idiom.
# SC2016/SC2088: the snippets handed to run_driver are single-quoted on
# purpose, so the shell under test expands $HOME and ~/ rather than this one;
# '~/.ssh/id_work' is the literal text the manifest is expected to hold.
# shellcheck disable=SC2015,SC2016,SC2088
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

# run_driver <shell> <snippet>
# Fresh HOME (with ~/.ssh/id_work and ~/.gitconfig including project-includes)
# and cwd per run; output in ${WORK}/out.log.
run_driver() {
    local sh="$1" snippet="$2"
    rm -rf "${WORK:?}/home" "${WORK:?}/cwd"
    mkdir -p "${WORK}/home/.ssh" "${WORK}/home/.config/git" "${WORK}/cwd"
    : > "${WORK}/home/.ssh/id_work"
    printf '[include]\n    path = ~/.config/git/project-includes\n' > "${WORK}/home/.gitconfig"
    # shellcheck disable=SC2016  # $0/$@ are for the inner shell, deliberately unexpanded
    (cd "${WORK}/cwd" && env -i HOME="${WORK}/home" PATH="${YQ_DIR}:${PATH}" \
        GIT_CONFIG_NOSYSTEM=1 GIT_SH="${GIT_SH}" \
        "${sh}" -c '. "$0" "$@"' "${WORK}/driver.sh" "${snippet}") >"${WORK}/out.log" 2>&1
}
show() { echo "--- output:"; cat "${WORK}/out.log"; }

HOME_DIR="${WORK}/home"
PROFILE="${HOME_DIR}/.config/git/profiles/personal-github.inc"
MANIFEST="${HOME_DIR}/.config/git/projects.yml"
KEY="${HOME_DIR}/.ssh/id_work"

# git_in <dir> <config key> — value git resolves there, with the run's HOME
git_in() {
    env -i HOME="${HOME_DIR}" PATH="${PATH}" GIT_CONFIG_NOSYSTEM=1 \
        git -C "$1" config --get "$2" 2>/dev/null
}

run_suite() { # <shell>
    local sh_name="$1" sh
    sh="$(command -v "${sh_name}" 2>/dev/null)"
    [[ -n "${sh}" ]] || { echo "SKIP: ${sh_name} not installed — ssh key checks not run under it"; return 0; }
    local want="ssh -i '${KEY}' -o IdentitiesOnly=yes"

    # ── 1. the profile gets core.sshCommand, with ~/ expanded and quoted ─────
    run_driver "${sh}" '_git_write_profile "${HOME}/p.inc" me@example.com "" "" "~/.ssh/id_work"'
    [[ "$(git config --file "${HOME_DIR}/p.inc" core.sshCommand)" == "${want}" ]] \
        && ok "[${sh_name}] a stored ~/ key is written as core.sshCommand with IdentitiesOnly, expanded and single-quoted" \
        || { fail "[${sh_name}] core.sshCommand is not '${want}'"; show; }

    run_driver "${sh}" '_git_write_profile "${HOME}/p.inc" me@example.com'
    [[ -z "$(git config --file "${HOME_DIR}/p.inc" core.sshCommand)" && -n "$(git config --file "${HOME_DIR}/p.inc" user.email)" ]] \
        && ok "[${sh_name}] without a key the profile has no core.sshCommand" \
        || { fail "[${sh_name}] a profile without a key has core.sshCommand, or lost its email"; show; }

    run_driver "${sh}" 'mkdir -p "${HOME}/my keys" && : > "${HOME}/my keys/id" && _git_write_profile "${HOME}/p.inc" me@example.com "" "" "${HOME}/my keys/id"'
    [[ "$(git config --file "${HOME_DIR}/p.inc" core.sshCommand)" == "ssh -i '${HOME_DIR}/my keys/id' -o IdentitiesOnly=yes" ]] \
        && ok "[${sh_name}] a path with a space is kept whole inside the quotes" \
        || { fail "[${sh_name}] a path with a space was not written as one quoted word"; show; }

    # ── 2. paths that could break out of the quotes are refused ──────────────
    run_driver "${sh}" '
        for k in "/k'"'"'x" "/k\"x" "/k\$x" "/k\`x" "/k\\x" "$(printf "/k\nx")" "relative/key" ""; do
            if _git_ssh_key_path_safe "${k}" >/dev/null 2>&1; then echo "ACCEPTED $(printf "%q" "${k}")"; else echo "REFUSED"; fi
        done'
    if [[ "$(grep -c '^REFUSED$' "${WORK}/out.log")" -eq 8 && "$(grep -c '^ACCEPTED' "${WORK}/out.log")" -eq 0 ]]; then
        ok "[${sh_name}] quote, double quote, \$, backtick, backslash, newline, a relative path and an empty path are all refused"
    else
        fail "[${sh_name}] an unsafe key path was accepted"; show
    fi

    run_driver "${sh}" '_git_write_profile "${HOME}/p.inc" me@example.com "" "" "/tmp/a\$(touch x)"; echo "RC $?"'
    if [[ -z "$(git config --file "${HOME_DIR}/p.inc" core.sshCommand 2>/dev/null)" && ! -e "${WORK}/cwd/x" ]] && grep -q '^WARN ' "${WORK}/out.log"; then
        ok "[${sh_name}] a hand-edited unsafe manifest value is warned about and never written to the profile"
    else
        fail "[${sh_name}] an unsafe stored key reached the profile"; show
    fi

    # ── 3. what the user is asked for: a readable file ───────────────────────
    run_driver "${sh}" '_git_ssh_key_check "${HOME}/.ssh/id_work"; echo "RC $?"'
    grep -qx 'RC 0' "${WORK}/out.log" \
        && ok "[${sh_name}] an existing key file passes the check" \
        || { fail "[${sh_name}] an existing key file was refused"; show; }

    run_driver "${sh}" '_git_ssh_key_check "${HOME}/.ssh/nope"; echo "RC $?"'
    grep -qx 'RC 1' "${WORK}/out.log" && grep -q '^ERROR .*not a readable file' "${WORK}/out.log" \
        && ok "[${sh_name}] a missing key file is refused with an error" \
        || { fail "[${sh_name}] a missing key file was not refused"; show; }

    run_driver "${sh}" ': > "${HOME}/.ssh/id_work.pub"; _git_ssh_key_check "${HOME}/.ssh/id_work.pub"; echo "RC $?"'
    grep -qx 'RC 0' "${WORK}/out.log" && grep -q '^WARN .*public key' "${WORK}/out.log" \
        && ok "[${sh_name}] a .pub file is warned about, not refused" \
        || { fail "[${sh_name}] a .pub file was refused or not warned about"; show; }

    # ── 4. command level (needs mikefarah yq v4) ─────────────────────────────
    if [[ -z "${YQ_FOUND}" ]]; then
        echo "SKIP: mikefarah yq v4 not found — command-level ssh key checks not run (set WB_TEST_YQ)"
        return 0
    fi

    run_driver "${sh}" 'git-add-project Personal GitHub me@example.com "" "" --no-cli --ssh-key "~/.ssh/id_work"; echo "RC $?"'
    if grep -qx 'RC 0' "${WORK}/out.log" \
        && [[ "$(git config --file "${PROFILE}" core.sshCommand)" == "${want}" ]] \
        && [[ "$("${YQ_FOUND}" '.projects[0].ssh_key' "${MANIFEST}")" == '~/.ssh/id_work' ]]; then
        ok "[${sh_name}] git-add-project --ssh-key writes the profile, and the manifest keeps the path as typed"
    else
        fail "[${sh_name}] git-add-project --ssh-key did not set both the profile and the manifest"; show
    fi

    run_driver "${sh}" 'git-add-project Personal GitHub me@example.com --ssh-key "${HOME}/.ssh/nope" --no-cli; echo "RC $?"'
    if grep -qx 'RC 1' "${WORK}/out.log" && [[ ! -e "${MANIFEST}" && ! -e "${PROFILE}" && ! -d "${HOME_DIR}/Projects" ]]; then
        ok "[${sh_name}] git-add-project with an unusable key stops before creating anything"
    else
        fail "[${sh_name}] git-add-project with an unusable key left files behind or returned 0"; show
    fi

    run_driver "${sh}" 'git-add-project Personal GitHub me@example.com --ssh-key; echo "RC $?"'
    grep -qx 'RC 1' "${WORK}/out.log" && grep -q '^ERROR --ssh-key requires a path' "${WORK}/out.log" \
        && ok "[${sh_name}] --ssh-key with no value is an error" \
        || { fail "[${sh_name}] --ssh-key with no value was not an error"; show; }

    # git picks the key up inside the project tree and nowhere else
    run_driver "${sh}" 'git-add-project Personal GitHub me@example.com --no-cli --ssh-key "~/.ssh/id_work" >/dev/null; git init -q "${HOME}/Projects/Personal/GitHub/repo"; git init -q "${HOME}/elsewhere"'
    if [[ "$(git_in "${HOME_DIR}/Projects/Personal/GitHub/repo" core.sshCommand)" == "${want}" && -z "$(git_in "${HOME_DIR}/elsewhere" core.sshCommand)" ]]; then
        ok "[${sh_name}] git resolves core.sshCommand inside the project tree, and not outside it"
    else
        fail "[${sh_name}] core.sshCommand did not apply to the project tree only"; show
    fi

    run_driver "${sh}" 'git-add-project Personal GitHub me@example.com --no-cli >/dev/null; git-update-project Personal GitHub --ssh-key "~/.ssh/id_work"; echo "RC $?"'
    if grep -qx 'RC 0' "${WORK}/out.log" \
        && [[ "$(git config --file "${PROFILE}" core.sshCommand)" == "${want}" ]] \
        && [[ "$("${YQ_FOUND}" '.projects[0].ssh_key' "${MANIFEST}")" == '~/.ssh/id_work' ]]; then
        ok "[${sh_name}] git-update-project --ssh-key adds a key to an existing project"
    else
        fail "[${sh_name}] git-update-project --ssh-key did not set both the profile and the manifest"; show
    fi

    run_driver "${sh}" 'git-add-project Personal GitHub me@example.com --no-cli --ssh-key "~/.ssh/id_work" >/dev/null; git-update-project Personal GitHub --ssh-key none; echo "RC $?"'
    if grep -qx 'RC 0' "${WORK}/out.log" \
        && [[ -z "$(git config --file "${PROFILE}" core.sshCommand)" ]] \
        && [[ "$("${YQ_FOUND}" '.projects[0] | has("ssh_key")' "${MANIFEST}")" == "false" ]] \
        && [[ "$(git config --file "${PROFILE}" user.email)" == "me@example.com" ]]; then
        ok "[${sh_name}] git-update-project --ssh-key none removes the key from profile and manifest, and keeps the rest"
    else
        fail "[${sh_name}] --ssh-key none did not remove the key cleanly"; show
    fi

    run_driver "${sh}" 'git-add-project Personal GitHub me@example.com --no-cli >/dev/null; git-update-project Personal GitHub --ssh-key none; echo "RC $?"'
    grep -q '^WARN No SSH key set' "${WORK}/out.log" \
        && ok "[${sh_name}] --ssh-key none on a project with no key says so" \
        || { fail "[${sh_name}] --ssh-key none with no key did not say so"; show; }

    run_driver "${sh}" 'git-add-project Personal GitHub me@example.com --no-cli >/dev/null; git-update-project Personal GitHub --ssh-key "${HOME}/.ssh/nope"; echo "RC $?"'
    if grep -qx 'RC 1' "${WORK}/out.log" && [[ -z "$(git config --file "${PROFILE}" core.sshCommand)" ]] \
        && [[ "$("${YQ_FOUND}" '.projects[0] | has("ssh_key")' "${MANIFEST}")" == "false" ]]; then
        ok "[${sh_name}] git-update-project --ssh-key with an unusable key changes nothing"
    else
        fail "[${sh_name}] an unusable key changed the profile or manifest"; show
    fi

    # list and status
    run_driver "${sh}" 'git-add-project Personal GitHub me@example.com --no-cli --ssh-key "~/.ssh/id_work" >/dev/null; git-add-project Work GitHub me@work.example --no-cli >/dev/null; git-list-projects'
    if grep -q 'SSH KEY' "${WORK}/out.log" && grep -q '^Personal .*~/.ssh/id_work$' "${WORK}/out.log" && grep -Eq '^Work .* -$' "${WORK}/out.log"; then
        ok "[${sh_name}] git-list-projects has an SSH KEY column: the path, or '-'"
    else
        fail "[${sh_name}] git-list-projects does not show the ssh key column"; show
    fi

    run_driver "${sh}" 'git-add-project Personal GitHub me@example.com --no-cli --ssh-key "~/.ssh/id_work" >/dev/null; git-sync-projects --status'
    grep -q 'ssh key: ✓.*~/.ssh/id_work' "${WORK}/out.log" \
        && ok "[${sh_name}] git-sync-projects --status shows a present key as ✓" \
        || { fail "[${sh_name}] --status does not show a present key"; show; }

    run_driver "${sh}" 'git-add-project Personal GitHub me@example.com --no-cli --ssh-key "~/.ssh/id_work" >/dev/null; rm "${HOME}/.ssh/id_work"; git-sync-projects --status'
    grep -q 'ssh key: ✗ missing.*~/.ssh/id_work' "${WORK}/out.log" \
        && ok "[${sh_name}] ...and a key file that has gone missing as ✗ missing" \
        || { fail "[${sh_name}] --status does not flag a missing key file"; show; }

    # sync recreates a missing profile with the key
    run_driver "${sh}" 'git-add-project Personal GitHub me@example.com --no-cli --ssh-key "~/.ssh/id_work" >/dev/null; rm "${HOME}/.config/git/profiles/personal-github.inc"; git-sync-projects >/dev/null'
    [[ "$(git config --file "${PROFILE}" core.sshCommand)" == "${want}" ]] \
        && ok "[${sh_name}] git-sync-projects writes the key into a profile it recreates" \
        || { fail "[${sh_name}] a profile recreated by sync has no core.sshCommand"; show; }
}

run_suite bash
run_suite zsh

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
[[ "${FAILED}" -eq 0 ]]
