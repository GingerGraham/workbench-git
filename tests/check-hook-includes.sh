#!/usr/bin/env bash
# tests/check-hook-includes.sh — workbench-git
# Plain bash, numbered OK:/FAIL: checks, matching workbench-core's
# tests/check-*.sh convention (no framework).
#
# Security review L6: hooks/post-deploy.sh used to `--unset-all
# include.path` unconditionally on every run, silently deleting any
# include.path line the user added themselves (e.g. a work-identity
# include, or a credential.helper override) before re-adding only
# workbench's own two paths. It now removes only its own two entries
# (--fixed-value), leaving the user's own lines untouched.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/post-deploy.sh"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

TEST_HOME="$(mktemp -d)"
trap 'rm -rf "${TEST_HOME}"' EXIT

# Isolate from the real user's global git config — a fresh $HOME with no
# GIT_CONFIG_GLOBAL override means git reads/writes ${TEST_HOME}/.gitconfig.
unset GIT_CONFIG_GLOBAL
export HOME="${TEST_HOME}"

USER_INCLUDE="${TEST_HOME}/.gitconfig-work"
touch "${USER_INCLUDE}"
git config --global --add include.path "${USER_INCLUDE}"

# Run the hook twice — post-deploy.sh must be idempotent (it runs on every
# `wb apply`, not just the first sync).
bash "${HOOK}" >/dev/null 2>&1
bash "${HOOK}" >/dev/null 2>&1

ALL_INCLUDES="$(git config --global --get-all include.path 2>/dev/null)"

if grep -qxF "${USER_INCLUDE}" <<<"${ALL_INCLUDES}"; then
    ok "user's own include.path entry is still present"
else
    fail "user's own include.path entry was removed"
fi

LOCAL_INC="${TEST_HOME}/.config/git/profiles/local.inc"
INCLUDES_FILE="${TEST_HOME}/.config/git/project-includes"

for path in "${LOCAL_INC}" "${INCLUDES_FILE}"; do
    count="$(grep -cxF "${path}" <<<"${ALL_INCLUDES}")"
    if [[ "${count}" -eq 1 ]]; then
        ok "workbench path appears exactly once: ${path}"
    else
        fail "workbench path appears ${count} time(s) (expected 1): ${path}"
    fi
done

first_line="$(head -n1 <<<"${ALL_INCLUDES}")"
if [[ "${first_line}" == "${USER_INCLUDE}" ]]; then
    ok "user's entry is listed first, ahead of workbench's own entries"
else
    fail "user's entry is not listed first (got: ${first_line})"
fi

# ── scenario 2: a real `--fixed-value` failure must not be masked ───────────
# A stub `git` that fails the --fixed-value --unset-all call the way an
# unsupported git (< 2.30) would, with an exit code that is not git's own
# "no entry matches" 5 — the hook must fail loudly rather than fall through
# to --add and duplicate the entry.
TEST_HOME_2="$(mktemp -d)"
STUB_BIN="$(mktemp -d)"
trap 'rm -rf "${TEST_HOME}" "${TEST_HOME_2}" "${STUB_BIN}"' EXIT

REAL_GIT="$(command -v git)"
cat > "${STUB_BIN}/git" <<STUBEOF
#!/usr/bin/env bash
if [[ "\$1" == "config" && "\$2" == "--global" && "\$3" == "--fixed-value" && "\$4" == "--unset-all" ]]; then
    exit 1
fi
exec "${REAL_GIT}" "\$@"
STUBEOF
chmod +x "${STUB_BIN}/git"

HOME="${TEST_HOME_2}" PATH="${STUB_BIN}:${PATH}" bash "${HOOK}" >/dev/null 2>/dev/null
hook_rc=$?

if [[ "${hook_rc}" -ne 0 ]]; then
    ok "hook exits non-zero when --fixed-value fails for a reason other than 'no match'"
else
    fail "hook exited 0 despite a real --fixed-value failure"
fi

stub_includes="$(HOME="${TEST_HOME_2}" git config --global --get-all include.path 2>/dev/null)"
stub_local_inc="${TEST_HOME_2}/.config/git/profiles/local.inc"
if ! grep -qxF "${stub_local_inc}" <<<"${stub_includes}"; then
    ok "no include.path entry was added after the failed unset (no silent duplicate)"
else
    fail "include.path was added despite the failed unset"
fi

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
[[ "${FAILED}" -eq 0 ]]
