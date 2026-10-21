# Changelog

All notable changes to `workbench-git` are documented here.

## [Unreleased]

## [0.2.3] - 2026-10-21

### Fixed

- **A `core.excludesfile` or `core.attributesfile` you set yourself is no
  longer replaced.** The post-deploy hook and `git-setup-identity` now set
  each only when it's unset, already workbench's, or points at a
  byte-identical copy of workbench's file; otherwise they keep yours and
  say where workbench's is (workbench-core D81, Phase 1 interim).

## [0.2.2] - 2026-10-10

### Security

- **`install-gh` now trusts only the pinned GitHub CLI key(s), stored
  locally** (review follow-up R1, R2; workbench-core D79). Previously a
  downloaded key file passed if it merely contained a pinned key, and the
  whole file was then imported into rpm or installed as the apt keyring, so
  any extra key in it was trusted too; and the dnf/yum repo kept a remote
  `gpgkey=https://...`, so a later `dnf -y` would import whatever that URL
  served. It now uses Core API 1.5's `_wb_dnf_vendor_repo`,
  `_wb_rpm_import_pinned_key` and `_wb_apt_keyring_pinned`: only the pinned
  primary keys are kept, the dnf/yum repo points at a local
  `gpgkey=file://...` copy and is limited to `gh` via `includepkgs`, and the
  repo file is rewritten on every run, replacing one left by an older
  version. A vendor key rotation now fails the install until this module
  ships a new pin.
- **The expired GitHub CLI key is no longer pinned.** Only the current key
  (`...313325`) is trusted. GitHub's served keyring still carries the old
  key (`...716059`, expired 2026-09-05); it is dropped with a warning
  instead of being trusted.

### Fixed

- **`install-gh` key verification always failed in zsh.** The pinned
  fingerprints were a space-separated string relied on to word-split, which
  zsh does not do, so both arrived as one bogus fingerprint. They are now an
  array.

### Changed

- `core_api:` raised to `">=1.5 <2.0"` for the Core API 1.5 vendor-key
  helpers.

## [0.2.1] - 2026-09-24

### Security

- **`GITHUB_PERSONAL_ACCESS_TOKEN` is no longer exported by default.** Both
  the eager, out-of-tree export in `shell/git.sh` and the per-project export
  in `use git_context` (`files/workbench-git-context.sh`) now require
  `export WORKBENCH_GIT_CONTEXT_EXPORT_TOKEN=true` in
  `~/.config/workbench/local/settings.sh` to opt in. An exported token is
  readable by every process the shell starts and typically carries `repo`
  and `workflow` scope.
- **`hooks/post-deploy.sh` no longer deletes the user's own `include.path`
  entries.** It used to run `git config --global --unset-all include.path`
  unconditionally on every run, then re-add only workbench's own two paths —
  silently dropping anything the user had added themselves (e.g. a
  work-identity include, or a `credential.helper` override). It now removes
  only its own two entries (`--fixed-value`) before re-adding them.
- **Installer downloads and third-party keys are now verified before use**
  (findings M3, M4). `install-gh`'s tarball fallback and `install-yq`'s
  binary install now check the downloaded asset's SHA-256 against the
  digest GitHub publishes for that release, refusing to install on a
  mismatch. `install-glab`'s `.deb`/`.rpm`/tarball paths verify against
  GitLab's own release `checksums.txt`. On Fedora, `install-gh` now
  prefers the distro's own signed `gh` package over adding GitHub's
  third-party rpm repo; when it does add that repo, it first verifies the
  repo's signing key against a pinned fingerprint (`rpm --import` only
  runs after that check) and constrains the repo to the `gh` package via
  `includepkgs`. `install-gh`'s Debian/apt path verifies the same pinned
  fingerprint before installing the downloaded apt keyring.
- Requires `workbench-core` Core API `>=1.4` (`core_api:` updated) for the
  new `_wb_fetch_verified`/`_wb_gh_asset_digest`/`_wb_key_has_fingerprint`
  helpers this depends on.

### Changed

- `core_api:` raised to `">=1.4 <2.0"`.

## [0.2.0] - 2026-09-22

### Added

- **Manual `workflow_dispatch` release override.** `release.yml` now
  accepts a `bump_type` (patch/minor/major) input to force a release
  through `workbench-core`'s reusable `module-release.yml`, regardless of
  what Conventional Commits since the last tag would compute — a floor,
  never a downgrade of a higher severity already pending. Manual dispatch
  only runs from `main`. See `workbench-core`'s `docs/decisions-log.md` D64.

## [0.1.2] - 2026-09-16

### Fixed

- yq-gated project-management functions (`git-list-projects`,
  `git-add-project`, `git-add-project-cli`, `git-remove-project-cli`,
  `git-update-project`, `git-remove-project`, `git-sync-projects`) no
  longer appear in `wb functions`/module-getter listings when yq is
  missing or the wrong variant (e.g. `python3-yq` shadowing
  mikefarah/yq v4) — they would previously list but immediately fail
  via `_git_require_yq`. Uses `workbench-core`'s new
  `_wb_alias_availability` predicate convention, backed by a quiet twin
  (`_git_yq_present`) of `_git_require_yq`'s existing version check.

## [0.1.1] - 2026-09-14

### Added

- **Agent-instruction files** (`AGENTS.md`, `CLAUDE.md`,
  `.github/copilot-instructions.md`,
  `.claude/skills/conventional-commits/SKILL.md`) — ports
  `workbench-core`'s D32 agent-instruction topology to this repo. See
  `workbench-core`'s `docs/decisions-log.md` D58.
- **Repo governance files** (`.github/PULL_REQUEST_TEMPLATE.md`,
  `.github/ISSUE_TEMPLATE/{bug_report,feature_request,config}.yml`,
  `.github/CODEOWNERS`, `CONTRIBUTING.md`, `SECURITY.md`) — ports
  `workbench-core`'s D31 governance-file topology to this repo, piloted
  here before the other ten module repos. See `workbench-core`'s
  `docs/decisions-log.md` D60.

## [0.1.0] - 2026-09-09

### Fixed

- Moved `files/attributes`/`files/ignore`'s `deploy:` destination from
  `~/.config/git/` to `~/.local/share/workbench/modules/git/files/` —
  `~/.config/git/` is on `workbench-core`'s `dest` denylist
  (`contracts/manifest-spec.md` §dest validation), so `manifest validate`
  was failing CI for every PR. `core.excludesfile`/`core.attributesfile`
  (set by `hooks/post-deploy.sh` and `git-setup-identity`) now point at the
  new location — no user-visible behaviour change. See README.md's "File
  ownership" table for the full explanation.

### Added

- Added `installed-gh`, `installed-glab`, `installed-yq` — reports install
  status to `wb tools upgrade`/`wb tools list --status` (workbench-core
  §12 D43).
- Initial decomposition from `workbench-precursor` (Wave C): git aliases,
  worktree helpers (`gwt`/`gwt-cd`), multi-context project identity
  management (`git-add-project`/`git-update-project`/`git-remove-project`/
  `git-list-projects`/`git-sync-projects`), CLI context wiring for `gh`/
  `glab` (`git-add-project-cli`/`git-remove-project-cli`), `gh`/`glab`
  shell completions, and `install-gh`/`install-glab`/`install-yq`.
- New `git-setup-identity` (interactive) — replaces the Ansible
  `gitconfig.j2` templating from `workbench-precursor`; no equivalent
  exists in `workbench-core`'s model, since setting git identity requires
  a human.
- `hooks/post-deploy.sh` (`run_on: initial`) scaffolds `projects.yml`,
  `project-includes`, `profiles/local.inc`, and wires
  `core.excludesfile`/`core.attributesfile`/`include.path` — replacing
  Ansible's one-time `~/.gitconfig`/`projects.yml` rendering.

### Changed

- Dropped the `host_vars/localhost.yml` mirror present in
  `workbench-precursor`'s `tools/git.sh` — `workbench-core` has no
  equivalent host_vars concept, so `projects.yml` is now the sole source
  of truth rather than one of two.
