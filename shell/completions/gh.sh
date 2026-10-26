#!/usr/bin/env bash
# GitHub CLI completions — version-stamped cache.

_gh_cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/workbench/completions"
_gh_version="$(gh --version 2>/dev/null | head -1 | awk '{print $3}')"

if [[ -n "${_gh_version}" ]]; then
    _gh_cache="${_gh_cache_dir}/gh.${WORKBENCH_SHELL}.${_gh_version}.sh"

    if [[ ! -f "${_gh_cache}" ]]; then
        mkdir -p "${_gh_cache_dir}"
        # nullglob: unmatched glob expands to nothing instead of erroring (zsh nomatch)
        if [[ -n "${ZSH_VERSION}" ]]; then
            setopt nullglob
        else
            shopt -s nullglob
        fi
        for _stale in "${_gh_cache_dir}"/gh."${WORKBENCH_SHELL}".*.sh; do
            [[ "${_stale}" != "${_gh_cache}" ]] && rm -f "${_stale}"
        done
        if [[ -n "${ZSH_VERSION}" ]]; then
            unsetopt nullglob
        else
            shopt -u nullglob
        fi
        unset _stale
        gh completion -s "${WORKBENCH_SHELL}" 2>/dev/null > "${_gh_cache}" \
            || rm -f "${_gh_cache}"
    fi

    # The generated zsh script calls compdef, which needs zsh's completion
    # system initialised first. Same idempotent guard as workbench-core's
    # shell/completions/wb.sh: -C reuses the existing dump, so this is a
    # no-op once compinit has run (e.g. from workbench-shell's zsh.sh).
    if [[ -n "${ZSH_VERSION:-}" ]] && ! command -v compdef &>/dev/null; then
        autoload -Uz compinit
        compinit -C
    fi

    # shellcheck disable=SC1090
    [[ -f "${_gh_cache}" ]] && source "${_gh_cache}"
fi

unset _gh_cache_dir _gh_version _gh_cache
