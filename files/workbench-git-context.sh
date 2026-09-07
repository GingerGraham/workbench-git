#!/usr/bin/env bash
# ~/.config/direnv/lib/workbench-git-context.sh
# Deployed by workbench-git — do not edit; regenerated on every sync.
# No user content lives here; per-project overrides belong in .envrc.local.
#
# direnv sources every *.sh in $XDG_CONFIG_HOME/direnv/lib/ into its own
# stdlib before evaluating any .envrc, and dispatches `use foo <args>` to a
# function named `use_foo`. This file backs:
#
#   use git_context <gh|glab> <context-slug> [host]
#
# See this repo's README.md#cli-context.
#
# NOTE: .envrc files — and this stdlib file — run inside direnv's own bash
# subshell, not the user's interactive shell. workbench-core's log_info/
# log_warn are never loaded here, so log_status/log_error (direnv's own
# stdlib) are used instead. This is the one place in workbench-git where
# that substitution is correct — do not "fix" it to use the usual helpers.

use_git_context() {
    local cli="${1:-}" ctx="${2:-}" host="${3:-}"
    # Hardcoded to ${HOME}/.config/git, matching shell/git.sh exactly (e.g.
    # _git_cli_config_dir) — not XDG-driven, unlike this file's own path
    # under $XDG_CONFIG_HOME/direnv/lib/. If XDG_CONFIG_HOME were honoured
    # here instead, a user with it set to a non-default location would get
    # GH_CONFIG_DIR pointed at an empty directory while git.sh keeps
    # writing to ${HOME}/.config/git, silently breaking CLI context wiring.
    local base="${HOME}/.config/git"

    [[ -z "${cli}" || -z "${ctx}" ]] && {
        log_status "use git_context: usage: use git_context <gh|glab> <context> [host]"
        return 1
    }

    case "${cli}" in
        gh)
            export GH_CONFIG_DIR="${base}/gh/${ctx}"
            [[ -n "${host}" ]] && export GH_HOST="${host}"

            # Context-aware token export — costs one keyring read per entry
            # into a project tree. Opt out with
            # WORKBENCH_GIT_CONTEXT_EXPORT_TOKEN=false in
            # ~/.config/workbench/local/settings.sh. No glab equivalent:
            # glab has no non-interactive token-print command matching
            # `gh auth token`.
            #
            # Always take ownership of GITHUB_PERSONAL_ACCESS_TOKEN here, in
            # both branches — an unauthenticated context must not leave the
            # previous context's (or the out-of-tree fallback's) token
            # exported, or anything reading the variable silently acts as
            # the wrong account. direnv snapshots and restores the outer
            # value on leaving the tree, so the unset is scoped correctly.
            if [[ "${WORKBENCH_GIT_CONTEXT_EXPORT_TOKEN:-true}" == "true" ]] \
               && command -v gh >/dev/null 2>&1; then
                local _tok
                _tok="$(gh auth token 2>/dev/null)"
                if [[ -n "${_tok}" ]]; then
                    export GITHUB_PERSONAL_ACCESS_TOKEN="${_tok}"
                else
                    unset GITHUB_PERSONAL_ACCESS_TOKEN
                fi
            fi
            ;;
        glab)
            export GLAB_CONFIG_DIR="${base}/glab/${ctx}"
            [[ -n "${host}" ]] && export GITLAB_HOST="${host}"
            :
            ;;
        *)
            log_status "use git_context: unknown CLI '${cli}'"
            return 1
            ;;
    esac
}
