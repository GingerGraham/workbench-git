#!/usr/bin/env bash
# tests/check-worktrees.sh — workbench-git
# Plain bash, numbered OK:/FAIL: checks, matching workbench-core's
# tests/check-*.sh convention (no framework).
#
# gwt puts worktrees under the repository root's .worktrees/, whatever the
# current directory; gwt-cd finds them through git, so a branch with a
# slash (feat/x, stored as .worktrees/feat-x) is found; gwt --local puts
# one in the current directory; and git-cleanup deletes branches whose
# upstream is gone by reading %(upstream:track), not `git branch -vv`
# columns (where the current branch reads "*" and a worktree's "+").
# Runs under bash and, when installed, zsh. Local repositories only.
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

command -v git >/dev/null 2>&1 || { echo "SKIP: git is not installed"; exit 0; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# Driver, sourced by whichever shell is under test: core's helpers stubbed,
# shell/git.sh sourced, then one scenario run inside ${REPO} ("$1").
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
    gwt)
        cd "${REPO}/sub" || exit 1
        gwt -b feat/x >/dev/null 2>&1
        echo "RC $?"
        gwt --local -b feat/y >/dev/null 2>&1
        echo "LOCAL_RC $?"
        cd "${REPO}/sub" || exit 1
        gwt-cd feat/x
        echo "CD_RC $?"
        echo "PWD $(pwd -P)"
        gwt-cd main
        echo "MAIN_PWD $(pwd -P)"
        ;;
    cleanup)
        cd "${REPO}" || exit 1
        git-cleanup 2>&1
        echo "RC $?"
        ;;
esac
DRIVER

# setup_repo: a repository with one commit on main, a sub/ directory, and a
# bare "origin" next to it. Fresh per run.
setup_repo() {
    rm -rf "${WORK:?}/home" "${WORK:?}/repo" "${WORK:?}/origin.git"
    mkdir -p "${WORK}/home"
    export HOME="${WORK}/home" GIT_CONFIG_NOSYSTEM=1
    git config --global user.name "Fixture User"
    git config --global user.email "fixture@example.invalid"
    git config --global init.defaultBranch main
    git init -q --bare "${WORK}/origin.git"
    git init -q "${WORK}/repo"
    mkdir -p "${WORK}/repo/sub"
    echo x > "${WORK}/repo/sub/file"
    git -C "${WORK}/repo" add -A
    git -C "${WORK}/repo" commit -q -m init
    git -C "${WORK}/repo" remote add origin "${WORK}/origin.git"
    git -C "${WORK}/repo" push -q -u origin main 2>/dev/null
}

run_driver() { # <shell> <scenario>
    # shellcheck disable=SC2016  # $0/$@ are for the inner shell, deliberately unexpanded
    REPO="${WORK}/repo" GIT_SH="${GIT_SH}" "$1" -c '. "$0" "$@"' "${WORK}/driver.sh" "$2" >"${WORK}/out.log" 2>&1
}
show() { echo "--- output:"; cat "${WORK}/out.log"; }
branch_exists() { git -C "${WORK}/repo" show-ref --verify --quiet "refs/heads/$1"; }

run_suite() { # <shell>
    local sh_name="$1" sh root
    sh="$(command -v "${sh_name}" 2>/dev/null)"
    [[ -n "${sh}" ]] || { echo "SKIP: ${sh_name} not installed — worktree checks not run under it"; return 0; }

    # ── 1. gwt / gwt-cd ─────────────────────────────────────────────────────
    setup_repo
    root="$(cd "${WORK}/repo" && pwd -P)"
    run_driver "${sh}" gwt
    [[ -d "${root}/.worktrees/feat-x" && ! -e "${root}/sub/.worktrees" ]] \
        && git -C "${root}" worktree list --porcelain | grep -qx "worktree ${root}/.worktrees/feat-x" \
        && ok "[${sh_name}] gwt -b feat/x from a subdirectory creates the worktree under the repo root" \
        || { fail "[${sh_name}] no worktree at ${root}/.worktrees/feat-x (or one under sub/)"; show; }
    [[ -d "${root}/sub/feat-y" ]] && grep -qx 'LOCAL_RC 0' "${WORK}/out.log" \
        && ok "[${sh_name}] gwt --local -b feat/y puts the worktree at ./feat-y" \
        || { fail "[${sh_name}] gwt --local did not create ./feat-y"; show; }
    grep -qx 'CD_RC 0' "${WORK}/out.log" && grep -qxF "PWD ${root}/.worktrees/feat-x" "${WORK}/out.log" \
        && ok "[${sh_name}] gwt-cd feat/x reaches it" \
        || { fail "[${sh_name}] gwt-cd feat/x did not reach ${root}/.worktrees/feat-x"; show; }
    grep -qxF "MAIN_PWD ${root}" "${WORK}/out.log" \
        && ok "[${sh_name}] gwt-cd main returns to the repo root" \
        || { fail "[${sh_name}] gwt-cd main did not reach ${root}"; show; }

    # ── 2. git-cleanup ──────────────────────────────────────────────────────
    # current (checked out here), wt-gone (checked out in another worktree)
    # and gone-br all lose their upstream; keep-br keeps it.
    setup_repo
    local b
    for b in current wt-gone gone-br keep-br; do
        git -C "${WORK}/repo" branch -q "${b}" main
        git -C "${WORK}/repo" push -q -u origin "${b}" 2>/dev/null
    done
    git -C "${WORK}/repo" checkout -q current
    git -C "${WORK}/repo" worktree add -q "${WORK}/wt" wt-gone 2>/dev/null
    for b in current wt-gone gone-br; do
        git -C "${WORK}/repo" push -q origin --delete "${b}" 2>/dev/null
    done
    run_driver "${sh}" cleanup
    ! branch_exists gone-br \
        && ok "[${sh_name}] git-cleanup deletes a branch whose upstream is gone, with another worktree checked out" \
        || { fail "[${sh_name}] gone-br was not deleted"; show; }
    branch_exists current && branch_exists wt-gone && branch_exists keep-br && branch_exists main \
        && ok "[${sh_name}] ...and leaves the current branch, the worktree's branch and live branches alone" \
        || { fail "[${sh_name}] a branch that should stay was deleted"; show; }
    if grep '^INFO Deleting branch ' "${WORK}/out.log" | grep -qvE '^INFO Deleting branch (current|wt-gone|gone-br)$'; then
        fail "[${sh_name}] git-cleanup tried to delete something that isn't a gone branch"; show
    else
        ok "[${sh_name}] ...and only ever names real branches (no '*' or '+' marker)"
    fi
    grep -qx 'RC 0' "${WORK}/out.log" \
        && ok "[${sh_name}] ...and returns 0" \
        || { fail "[${sh_name}] git-cleanup did not return 0"; show; }
    git -C "${WORK}/repo" worktree remove --force "${WORK}/wt" 2>/dev/null
}

run_suite bash
run_suite zsh

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
[[ "${FAILED}" -eq 0 ]]
