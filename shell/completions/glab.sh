#!/usr/bin/env bash
# GitLab CLI completions — version-stamped cache.

_glab_cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/workbench/completions"
_glab_version="$(glab --version 2>/dev/null | head -1 | awk '{print $3}')"

if [[ -n "${_glab_version}" ]]; then
    _glab_cache="${_glab_cache_dir}/glab.${WORKBENCH_SHELL}.${_glab_version}.sh"

    if [[ ! -f "${_glab_cache}" ]]; then
        mkdir -p "${_glab_cache_dir}"
        if [[ -n "${ZSH_VERSION}" ]]; then
            setopt nullglob
        else
            shopt -s nullglob
        fi
        for _stale in "${_glab_cache_dir}"/glab."${WORKBENCH_SHELL}".*.sh; do
            [[ "${_stale}" != "${_glab_cache}" ]] && rm -f "${_stale}"
        done
        if [[ -n "${ZSH_VERSION}" ]]; then
            unsetopt nullglob
        else
            shopt -u nullglob
        fi
        unset _stale
        glab completion -s "${WORKBENCH_SHELL}" 2>/dev/null > "${_glab_cache}" \
            || rm -f "${_glab_cache}"
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
    [[ -f "${_glab_cache}" ]] && source "${_glab_cache}"
fi

unset _glab_cache_dir _glab_version _glab_cache
