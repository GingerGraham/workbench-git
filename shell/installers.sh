#!/usr/bin/env bash
# shell/installers.sh — workbench-git
# install-gh, install-glab, install-yq and their per-distro helpers.
# Ported from workbench-precursor's lazy/installers-dev.sh (the gh/glab/yq
# slice — that file split five ways across Wave C modules, per the module
# map's own §7 call-out). _download_file_robust/_node_version_at_least come
# from workbench-core's lib/core/installers-common.sh (Core API, tier:
# core) — not duplicated here.
#
# WORKBENCH_OS/WORKBENCH_DISTRO are workbench-core Core API platform facts
# (contracts/core-api.md), replacing the precursor's DOTFILES_OS/DOTFILES_DISTRO.

# _gh_release_asset_url <api_response_json> <extended_regex_pattern>
# Extracts the first browser_download_url whose filename matches <pattern>.
# Splits each browser_download_url onto its own line before filtering — a
# GitHub API response is one unbroken line, so a plain grep+sed here would
# let a greedy regex match across every asset in the release rather than
# just the one wanted, silently returning the wrong file.
_gh_release_asset_url() {
    local api_response="$1" pattern="$2"
    printf '%s' "${api_response}" \
        | grep -Eo '"browser_download_url": *"[^"]+"' \
        | sed -E 's/.*"(https[^"]+)"/\1/' \
        | grep -E "${pattern}" \
        | head -1
}

# ── GitHub CLI install ────────────────────────────────────────────────────────

# DNF5 (Fedora 41+) and DNF4 use different config-manager syntax.
_gh_dnf_is_v5() {
    command -v dnf5 &>/dev/null && return 0
    dnf --version 2>/dev/null | head -1 | grep -qiE 'dnf5|^5\.'
}

_gh-install-rhel() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    [[ "${elevation_cmd}" == "run0" ]] && log_warn "run0 detected — multiple prompts expected"
    local repo_url="https://cli.github.com/packages/rpm/gh-cli.repo"

    if command -v dnf &>/dev/null; then
        if _gh_dnf_is_v5; then
            log_info "Configuring GitHub CLI repo (dnf5)..."
            ${elevation_cmd} dnf install -y dnf5-plugins
            ${elevation_cmd} dnf config-manager addrepo --from-repofile="${repo_url}" || true
        else
            log_info "Configuring GitHub CLI repo (dnf4)..."
            ${elevation_cmd} dnf install -y 'dnf-command(config-manager)'
            ${elevation_cmd} dnf config-manager --add-repo "${repo_url}"
        fi
        ${elevation_cmd} dnf install -y gh
    elif command -v yum &>/dev/null; then
        log_info "Configuring GitHub CLI repo (yum)..."
        command -v yum-config-manager &>/dev/null || ${elevation_cmd} yum install -y yum-utils
        ${elevation_cmd} yum-config-manager --add-repo "${repo_url}"
        ${elevation_cmd} yum install -y gh
    else
        log_error "Neither dnf nor yum found"; return 1
    fi
}

_gh-install-debian() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    if ! command -v wget &>/dev/null; then
        log_info "Installing wget (required to fetch the keyring)..."
        ${elevation_cmd} apt-get update && ${elevation_cmd} apt-get install -y wget
    fi
    local keyring="/etc/apt/keyrings/githubcli-archive-keyring.gpg"
    ${elevation_cmd} mkdir -p -m 755 /etc/apt/keyrings
    local tmp; tmp="$(mktemp)"
    if ! wget -nv -O "${tmp}" https://cli.github.com/packages/githubcli-archive-keyring.gpg; then
        log_error "Failed to download GitHub CLI keyring"; rm -f "${tmp}"; return 1
    fi
    ${elevation_cmd} install -m 644 "${tmp}" "${keyring}"
    rm -f "${tmp}"
    ${elevation_cmd} mkdir -p -m 755 /etc/apt/sources.list.d
    echo "deb [arch=$(dpkg --print-architecture) signed-by=${keyring}] https://cli.github.com/packages stable main" \
        | ${elevation_cmd} tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    ${elevation_cmd} apt-get update
    ${elevation_cmd} apt-get install -y gh
}

_gh-install-suse() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    local repo_url="https://cli.github.com/packages/rpm/gh-cli.repo"
    if zypper lr 2>/dev/null | grep -qi 'gh-cli'; then
        log_info "GitHub CLI zypper repo already present"
    else
        ${elevation_cmd} zypper addrepo "${repo_url}"
    fi
    ${elevation_cmd} zypper --gpg-auto-import-keys ref
    ${elevation_cmd} zypper install -y gh
}

_gh-install-arch() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    ${elevation_cmd} pacman -S --noconfirm github-cli
}

_gh-install-mac() {
    command -v brew &>/dev/null || { log_error "Homebrew required on macOS"; return 1; }
    if command -v gh &>/dev/null; then brew upgrade gh; else brew install gh; fi
}

# Distro-independent fallback: latest release tarball → ~/.local/bin/gh
_gh-install-tarball() {
    log_info "Falling back to a distro-independent binary install from GitHub releases..."
    command -v tar &>/dev/null || { log_error "tar is required for the fallback install"; return 1; }

    local api_response ver ver_num
    api_response="$(curl -s https://api.github.com/repos/cli/cli/releases/latest)"
    ver="$(printf '%s' "${api_response}" | grep '"tag_name":' \
        | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' | head -1)"
    [[ -z "${ver}" ]] && { log_error "Could not determine latest gh version (GitHub API rate limit?)"; return 1; }
    ver_num="${ver#v}"

    # Go-style arch naming — see docs/module-authoring.md's normalization
    # snippet in workbench-core; this is the amd64/arm64 variant.
    local arch ext
    case "${WORKBENCH_ARCH}" in
        x86_64)        arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) log_error "Unsupported architecture: ${WORKBENCH_ARCH}"; return 1 ;;
    esac
    local os
    case "${WORKBENCH_OS}" in
        Linux) os="linux"; ext="tar.gz" ;;
        Mac)   os="macOS"; ext="zip"    ;;
        *) log_error "Unsupported OS: ${WORKBENCH_OS}"; return 1 ;;
    esac

    local asset="gh_${ver_num}_${os}_${arch}.${ext}"
    local url="https://github.com/cli/cli/releases/download/${ver}/${asset}"
    local tmp_dir; tmp_dir="$(mktemp -d)"

    log_info "Downloading ${asset}..."
    _download_file_robust "${url}" "${tmp_dir}/${asset}" || { rm -rf "${tmp_dir}"; return 1; }

    if [[ "${ext}" == "zip" ]]; then
        command -v unzip &>/dev/null || { log_error "unzip is required"; rm -rf "${tmp_dir}"; return 1; }
        unzip -q "${tmp_dir}/${asset}" -d "${tmp_dir}"
    else
        tar -xzf "${tmp_dir}/${asset}" -C "${tmp_dir}"
    fi

    local bin; bin="$(find "${tmp_dir}" -type f -path '*/bin/gh' | head -1)"
    [[ -z "${bin}" ]] && bin="$(find "${tmp_dir}" -type f -name gh -perm -u+x | head -1)"
    if [[ -z "${bin}" ]]; then
        log_error "gh binary not found in archive"; rm -rf "${tmp_dir}"; return 1
    fi
    mkdir -p "${HOME}/.local/bin"
    install -m 755 "${bin}" "${HOME}/.local/bin/gh"
    rm -rf "${tmp_dir}"
    log_info "gh installed to ~/.local/bin/gh"
    [[ ":${PATH}:" != *":${HOME}/.local/bin:"* ]] \
        && log_warn "${HOME}/.local/bin is not on PATH — add it in ~/.config/workbench/local/settings.sh"
}

install-gh() {
    log_info "Installing or updating GitHub CLI (gh)..."
    command -v curl &>/dev/null || { log_error "curl is required"; return 1; }

    case "${WORKBENCH_OS}" in
        Mac)
            _gh-install-mac
            ;;
        Linux)
            local ok=1
            case "${WORKBENCH_DISTRO}" in
                rhel)   _gh-install-rhel   && ok=0 ;;
                debian) _gh-install-debian && ok=0 ;;
                suse)   _gh-install-suse   && ok=0 ;;
                arch)   _gh-install-arch   && ok=0 ;;
                *)      log_warn "Unknown distro (${WORKBENCH_DISTRO}) — using distro-independent install" ;;
            esac
            [[ "${ok}" -ne 0 ]] && { _gh-install-tarball || return 1; }
            ;;
        *)
            log_error "Unsupported OS for gh install"; return 1
            ;;
    esac

    if command -v gh &>/dev/null; then
        log_info "GitHub CLI installed: $(gh --version 2>/dev/null | head -1)"
        echo
        echo "  Authenticate with:"
        echo "    gh auth login"
    else
        log_warn "gh not found in PATH after install. Restart your shell or check ~/.local/bin."
    fi
}

# ── GitLab CLI install ────────────────────────────────────────────────────────
# Fedora/RHEL: official dnf/yum repo package 'glab'.
# Arch: official 'extra/glab' via pacman.
# Debian/Ubuntu, openSUSE: no vendor apt/zypper repo exists, but GitLab attaches
#   native .deb/.rpm packages to every release — download + install directly.
# macOS: Homebrew.
# Fallback (native path failed, or distro unrecognised): Homebrew/Linuxbrew if
#   present, else the distro-independent release tarball.
#
# Snap is deliberately NOT used. glab ships as a strict-confinement snap, and
# strict snaps' only $HOME access (the "home" interface) cannot read or create
# hidden directories at all — confirmed as intentional snapd behaviour
# (https://bugs.launchpad.net/snapd/+bug/1979060). glab's config lives at
# ~/.config/glab-cli, a hidden directory, so the snap can never write it.

_glab-install-rhel() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    if command -v dnf &>/dev/null; then
        ${elevation_cmd} dnf install -y glab
    elif command -v yum &>/dev/null; then
        ${elevation_cmd} yum install -y glab
    else
        log_error "Neither dnf nor yum found"; return 1
    fi
}

_glab-install-arch() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    ${elevation_cmd} pacman -S --noconfirm glab
}

# Shared: latest glab tag and arch suffix, used by the debian/suse/tarball paths.
_glab-latest-tag() {
    curl -s "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases?order_by=released_at&sort=desc&per_page=1" \
        | grep -o '"tag_name": *"[^"]*"' \
        | head -1 \
        | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
}

_glab-arch-suffix() {
    case "${WORKBENCH_ARCH}" in
        x86_64)        echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) log_error "Unsupported architecture: ${WORKBENCH_ARCH}"; return 1 ;;
    esac
}

# Direct .deb download from the GitLab release — no apt repo exists for glab.
_glab-install-debian() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    local ver ver_num arch asset url tmp_dir
    ver="$(_glab-latest-tag)"; [[ -z "${ver}" ]] && { log_error "Could not determine latest glab version"; return 1; }
    ver_num="${ver#v}"
    arch="$(_glab-arch-suffix)" || return 1

    asset="glab_${ver_num}_linux_${arch}.deb"
    url="https://gitlab.com/gitlab-org/cli/-/releases/${ver}/downloads/${asset}"
    tmp_dir="$(mktemp -d)"

    log_info "Downloading ${asset}..."
    _download_file_robust "${url}" "${tmp_dir}/${asset}" || { rm -rf "${tmp_dir}"; return 1; }
    ${elevation_cmd} dpkg -i "${tmp_dir}/${asset}" || ${elevation_cmd} apt-get install -f -y
    rm -rf "${tmp_dir}"
}

# Direct .rpm download from the GitLab release — no zypper repo exists for glab.
_glab-install-suse() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    local ver ver_num arch asset url tmp_dir
    ver="$(_glab-latest-tag)"; [[ -z "${ver}" ]] && { log_error "Could not determine latest glab version"; return 1; }
    ver_num="${ver#v}"
    arch="$(_glab-arch-suffix)" || return 1

    asset="glab_${ver_num}_linux_${arch}.rpm"
    url="https://gitlab.com/gitlab-org/cli/-/releases/${ver}/downloads/${asset}"
    tmp_dir="$(mktemp -d)"

    log_info "Downloading ${asset}..."
    _download_file_robust "${url}" "${tmp_dir}/${asset}" || { rm -rf "${tmp_dir}"; return 1; }
    ${elevation_cmd} zypper install -y "${tmp_dir}/${asset}"
    rm -rf "${tmp_dir}"
}

_glab-install-brew() {
    command -v brew &>/dev/null || { log_error "Homebrew not found"; return 1; }
    if command -v glab &>/dev/null; then brew upgrade glab; else brew install glab; fi
}

_glab-install-mac() {
    _glab-install-brew
}

# Distro-independent fallback: latest release tarball → ~/.local/bin/glab
_glab-install-tarball() {
    log_info "Falling back to distro-independent binary from GitLab releases..."
    command -v tar &>/dev/null || { log_error "tar is required for the fallback install"; return 1; }

    local ver ver_num arch asset url tmp_dir bin
    ver="$(_glab-latest-tag)"; [[ -z "${ver}" ]] && { log_error "Could not determine latest glab version (GitLab API unavailable?)"; return 1; }
    ver_num="${ver#v}"
    arch="$(_glab-arch-suffix)" || return 1

    # GitLab release assets use lowercase "linux" (glab_<ver>_linux_<arch>.tar.gz)
    # since the GitLab org took over the project — the old profclems/glab
    # releases used "Linux", which is what broke this before.
    asset="glab_${ver_num}_linux_${arch}.tar.gz"
    url="https://gitlab.com/gitlab-org/cli/-/releases/${ver}/downloads/${asset}"
    tmp_dir="$(mktemp -d)"

    log_info "Downloading ${asset}..."
    _download_file_robust "${url}" "${tmp_dir}/${asset}" || { rm -rf "${tmp_dir}"; return 1; }
    if ! tar -xzf "${tmp_dir}/${asset}" -C "${tmp_dir}"; then
        log_error "Archive did not extract — asset naming may have changed upstream again"
        rm -rf "${tmp_dir}"; return 1
    fi

    bin="$(find "${tmp_dir}" -type f -name glab -perm -u+x | head -1)"
    if [[ -z "${bin}" ]]; then
        log_error "glab binary not found in archive"; rm -rf "${tmp_dir}"; return 1
    fi
    mkdir -p "${HOME}/.local/bin"
    install -m 755 "${bin}" "${HOME}/.local/bin/glab"
    rm -rf "${tmp_dir}"
    log_info "glab installed to ~/.local/bin/glab"
    [[ ":${PATH}:" != *":${HOME}/.local/bin:"* ]] \
        && log_warn "${HOME}/.local/bin is not on PATH — add it in ~/.config/workbench/local/settings.sh"
}

# Used if the matching native path above failed, or the distro is unrecognised:
# Homebrew/Linuxbrew if present, then the release tarball as the last resort.
_glab-install-fallback-chain() {
    if command -v brew &>/dev/null; then
        log_info "Homebrew detected — installing glab via brew..."
        _glab-install-brew && return 0
        log_warn "Homebrew install failed — trying the release tarball..."
    fi
    _glab-install-tarball
}

install-glab() {
    log_info "Installing or updating GitLab CLI (glab)..."
    command -v curl &>/dev/null || { log_error "curl is required"; return 1; }

    case "${WORKBENCH_OS}" in
        Mac)
            _glab-install-mac
            ;;
        Linux)
            local ok=1
            case "${WORKBENCH_DISTRO}" in
                rhel)   _glab-install-rhel   && ok=0 ;;
                arch)   _glab-install-arch   && ok=0 ;;
                debian) _glab-install-debian && ok=0 ;;
                suse)   _glab-install-suse   && ok=0 ;;
            esac
            if [[ "${ok}" -ne 0 ]]; then
                log_info "No working native package path for glab — trying brew/tarball..."
                _glab-install-fallback-chain || return 1
            fi
            ;;
        *)
            log_error "Unsupported OS for glab install"; return 1
            ;;
    esac

    if command -v glab &>/dev/null; then
        log_info "GitLab CLI installed: $(glab --version 2>/dev/null | head -1)"
        echo
        echo "  Authenticate with:"
        echo "    glab auth login"
    else
        log_warn "glab not found in PATH after install. Restart your shell or check ~/.local/bin."
    fi
}

# ── yq (mikefarah/yq v4) install ──────────────────────────────────────────────
# Required by git.sh's manifest operations. Package availability varies:
#   - Fedora: yq is in base repos
#   - RHEL 9+: EPEL (attempt and fall through on failure)
#   - Ubuntu/Debian: apt ships yq 3.x (Python wrapper, wrong tool) — skip apt
#   - openSUSE: third-party OBS repo only — not worth adding a repo for
#   - Arch: AUR `yq` package
# Binary install is therefore the primary path for debian and suse.

_yq-install-rhel() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    if command -v dnf &>/dev/null; then
        if ! ${elevation_cmd} dnf install -y yq 2>/dev/null; then
            log_info "yq: not found in base repos, attempting via EPEL..."
            ${elevation_cmd} dnf install -y epel-release 2>/dev/null || true
            ${elevation_cmd} dnf install -y yq
        fi
    elif command -v yum &>/dev/null; then
        if ! ${elevation_cmd} yum install -y yq 2>/dev/null; then
            log_info "yq: not found in base repos, attempting via EPEL..."
            ${elevation_cmd} yum install -y epel-release 2>/dev/null || true
            ${elevation_cmd} yum install -y yq
        fi
    else
        log_error "yq: neither dnf nor yum found"; return 1
    fi
}

_yq-install-arch() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    if command -v yay &>/dev/null; then
        yay -S --noconfirm yq
    else
        ${elevation_cmd} pacman -S --noconfirm yq
    fi
}

_yq-install-mac() {
    command -v brew &>/dev/null || { log_error "brew is required on macOS"; return 1; }
    if command -v yq &>/dev/null; then brew upgrade yq; else brew install yq; fi
}

_yq-install-binary() {
    log_info "yq: installing binary from GitHub releases..."
    command -v curl &>/dev/null || { log_error "curl is required"; return 1; }

    local api_response ver arch url tmp_dir
    api_response="$(curl -s https://api.github.com/repos/mikefarah/yq/releases/latest)"
    ver="$(printf '%s' "${api_response}" | grep '"tag_name":' \
        | sed -E 's/.*"tag_name": *"v?([^"]+)".*/\1/' | head -1)"
    [[ -z "${ver}" ]] && { log_error "yq: could not determine latest version"; return 1; }

    case "${WORKBENCH_ARCH}" in
        x86_64)        arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) log_error "yq: unsupported architecture ${WORKBENCH_ARCH}"; return 1 ;;
    esac

    # yq releases a plain binary — no archive to extract
    url="$(_gh_release_asset_url "${api_response}" "yq_linux_${arch}$")"
    [[ -z "${url}" ]] \
        && url="https://github.com/mikefarah/yq/releases/download/v${ver}/yq_linux_${arch}"

    tmp_dir="$(mktemp -d)"
    _download_file_robust "${url}" "${tmp_dir}/yq" || { rm -rf "${tmp_dir}"; return 1; }
    mkdir -p "${HOME}/.local/bin"
    install -m 755 "${tmp_dir}/yq" "${HOME}/.local/bin/yq"
    rm -rf "${tmp_dir}"
    log_info "yq ${ver} installed to ~/.local/bin/yq"
}

install-yq() {
    log_info "Installing or updating yq..."

    case "${WORKBENCH_OS}" in
        Mac) _yq-install-mac; return $? ;;
        Linux) ;;
        *) log_error "Unsupported OS for yq install"; return 1 ;;
    esac

    local ok=1
    case "${WORKBENCH_DISTRO}" in
        rhel)   _yq-install-rhel && ok=0 ;;
        arch)   _yq-install-arch && ok=0 ;;
        # debian: apt ships yq 3.x (wrong tool) — go straight to binary
        # suse: only in third-party OBS repo — not worth a repo add, use binary
        debian|suse|*) log_info "yq: no suitable distro package — using binary install" ;;
    esac
    [[ "${ok}" -ne 0 ]] && { _yq-install-binary || return 1; }

    # Verify it's the mikefarah variant, not the Python yq 3.x wrapper
    if command -v yq &>/dev/null; then
        local installed_ver
        installed_ver="$(yq --version 2>/dev/null | head -1)"
        if printf '%s' "${installed_ver}" | grep -qiE '(https://github.com/mikefarah|mikefarah)'; then
            log_info "yq installed: ${installed_ver}"
        else
            log_warn "yq on PATH appears to be a different implementation: ${installed_ver}"
            log_warn "The mikefarah binary was installed to ~/.local/bin/yq — check PATH ordering."
        fi
    else
        log_warn "yq not on PATH after install — check ~/.local/bin is in PATH"
    fi
}
