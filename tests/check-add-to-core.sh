#!/usr/bin/env bash
# tests/check-add-to-core.sh — workbench-git
# Run by workbench-core's module CI ("add to core", step 8) with WB,
# MODULE_NAME, MODULE_URL, MODULE_BRANCH and MODULE_ROOT set. Builds its own
# scratch HOME seeded with a user's ~/.gitconfig — including the lines the
# pre-D82 post-deploy hook wrote — then adds this branch of the module the
# way the shared check does, and proves the gitconfig layers
# (workbench-core docs/decisions-log.md D82): the user's settings win, the
# module's defaults apply underneath, the identity is untouched, and the
# old hook lines are gone.
#
# SC2015: '[[ cond ]] && ok || fail' is this suite's assertion idiom.
# SC2088: '~/...' is compared literally — it is what files/gitconfig sets.
# shellcheck disable=SC2015,SC2088
set -uo pipefail

# Module CI's structural-tests job also runs every tests/check-*.sh on its
# own, without a core checkout: nothing to add the module to there.
if [[ -z "${WB:-}" || -z "${MODULE_NAME:-}" || -z "${MODULE_URL:-}" || -z "${MODULE_BRANCH:-}" ]]; then
    echo "SKIP: needs WB, MODULE_NAME, MODULE_URL and MODULE_BRANCH — run by workbench-core's module CI ('add to core', step 8)"
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

# A user's own ~/.gitconfig, plus what the old hook appended (absolute,
# $HOME-expanded paths — the form it wrote).
cat > "${HOME}/.gitconfig" <<EOF
[user]
	name = Fixture User
	email = fixture@example.invalid
[init]
	defaultBranch = trunk
[core]
	excludesfile = ${HOME}/.local/share/workbench/modules/git/files/ignore
	attributesfile = ${HOME}/.local/share/workbench/modules/git/files/attributes
[include]
	path = ${HOME}/.config/git/profiles/local.inc
	path = ${HOME}/.config/git/project-includes
EOF

run() { "$@" >"${WORK}/out.log" 2>&1 || { echo "--- $* failed:"; cat "${WORK}/out.log"; return 1; }; }
run "${WB}" add "${MODULE_NAME}" "${MODULE_URL}" --keep-files </dev/null || fail "wb add"
run "${WB}" track "${MODULE_NAME}" --branch "${MODULE_BRANCH}" </dev/null || fail "wb track"
run "${WB}" update "${MODULE_NAME}" </dev/null || fail "wb update"

G="${HOME}/.gitconfig"
get() { git config --file "${G}" --includes --get "$1" 2>/dev/null; }

[[ "$(get init.defaultBranch)" == "trunk" ]] \
    && ok "your init.defaultBranch (trunk) wins over the module's default" \
    || fail "init.defaultBranch is '$(get init.defaultBranch)'"
[[ "$(get push.autoSetupRemote)" == "true" ]] \
    && ok "the module's push.autoSetupRemote applies where you set none" \
    || fail "push.autoSetupRemote is '$(get push.autoSetupRemote)'"
[[ "$(get user.name)" == "Fixture User" && "$(get user.email)" == "fixture@example.invalid" ]] \
    && ok "your identity is unchanged" \
    || fail "identity: '$(get user.name)' <$(get user.email)>"
[[ "$(get core.excludesfile)" == "~/.local/share/workbench/modules/git/files/ignore" ]] \
    && ok "core.excludesfile now comes from the layer" \
    || fail "core.excludesfile is '$(get core.excludesfile)'"

if grep -q "path = ${HOME}/.config/git/" "${G}" || grep -q "excludesfile = ${HOME}/" "${G}"; then
    fail "the old hook's lines are still in ~/.gitconfig:"; cat "${G}"
else
    ok "the old hook's include.path and core.* lines are gone"
fi
[[ "$(head -n 1 "${G}")" == "# >>> workbench ${MODULE_NAME}/gitconfig under >>>" \
    && "$(tail -n 1 "${G}")" == "# <<< workbench ${MODULE_NAME}/gitconfig over <<<" ]] \
    && ok "defaults block at the top, project-contexts block at the end" \
    || { fail "block positions"; cat "${G}"; }
[[ "$(git config --file "${G}" --includes --get-all include.path | grep -c 'config/git/project-includes')" -eq 1 ]] \
    && ok "project-includes is included exactly once" \
    || fail "project-includes included $(git config --file "${G}" --includes --get-all include.path | grep -c 'config/git/project-includes') times"

# Core's "add to core" step runs only this file with WB/MODULE_* set, so
# check-yq-availability.sh, which also needs a core, runs from here. It
# builds its own HOME.
if bash "$(dirname "${BASH_SOURCE[0]}")/check-yq-availability.sh" >"${WORK}/yq-availability.log" 2>&1; then
    ok "tests/check-yq-availability.sh passed"
else
    fail "tests/check-yq-availability.sh failed:"
fi
cat "${WORK}/yq-availability.log"

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
[[ "${FAILED}" -eq 0 ]]
