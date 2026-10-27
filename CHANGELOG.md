# Changelog

All notable changes to `workbench-git` are documented here.

## [Unreleased]

## [1.0.1] - 2026-10-27

### Fixed

- **`wb tools install yq` on Arch installs mikefarah's yq v4.** Arch's
  `yq` package is the Python wrapper (kislyuk/yq), not the yq
  workbench-git needs, and with `yay` present the installer went through
  the AUR. It now runs `pacman -S --needed --noconfirm go-yq`, Arch's
  official package for mikefarah's yq, and never uses `yay`. If the
  Python `yq` is already installed, pacman reports the conflict and the
  installer falls back to the verified binary in `~/.local/bin`.

## [1.0.0] - 2026-10-27

### Fixed

- **zsh with `gh` or `glab` installed no longer prints `command not found:
  compdef` at start.** Their cached completions are sourced only after
  zsh's completion system is initialised, with the same guard
  workbench-core uses for `wb`'s own completions.

- **CLI contexts work the first time you `cd` into the project.** direnv
  blocks a new or changed `.envrc` until it is allowed, so after
  `git-add-project-cli` the context's `GH_CONFIG_DIR` was never set and
  `gh auth login` stored credentials in the default `~/.config/gh`.
  workbench-git now runs `direnv allow` on the `.envrc` it generates,
  including one that is already up to date (a project wired before this
  fix). Without direnv installed, the `.envrc` is still written and the
  warning gives the `direnv allow <path>` to run once it is.
- Because the generated `.envrc` is now allowed automatically, the values
  written into it are checked first: the context slug must use only
  `a-z 0-9 . _ -`, the CLI must be `gh` or `glab`, and a host must be a
  hostname with an optional `:port`. Anything else is refused with an
  error and no `.envrc` is written. Anything in `.envrc.local` runs once
  the generated file is allowed (README, "CLI context").
- **`get-git-functions` lists the functions and aliases in zsh too.** The
  hand-written getter used `${BASH_SOURCE[0]}`, which zsh doesn't set, so
  in zsh it printed `(none)`. workbench-core now generates the getter from
  `register.getters[]` (workbench-core D89). Its headers read
  `[INFO] Git identity, project-context, and CLI-wiring helpers —
  functions:` and `… — aliases:`, and it no longer lists itself.

- **`git-cleanup` deletes the right branches.** It read the first column of
  `git branch -vv`, which is `*` for the current branch and `+` for one
  checked out in another worktree, so it ran `git branch -D` on the marker
  (or, unquoted, on file names `*` matched). It now reads each branch's
  upstream state (`%(upstream:track)` is `[gone]`), stops if `git fetch -p`
  fails, and warns instead of failing silently when a branch can't be
  deleted because a worktree has it checked out.
- **`gwt` and `gwt-cd` agree on where worktrees live.** `gwt` created
  `.worktrees/` in the current directory and named `feat/x` as `feat-x`,
  while `gwt-cd` looked for `.worktrees/feat/x` in the current directory.
  `gwt` now always uses `<repo root>/.worktrees/`, from any subdirectory or
  worktree, and `gwt-cd` asks git where a branch's worktree is.
  `gwt-cd main` returns to the main worktree from inside a linked one.
  `gwt --local <branch>` (which ran `git worktree add .` and always failed)
  now creates `./<branch>` in the current directory, slashes as dashes.
- **Setting a signing key no longer breaks every commit on a host without
  gpg.** `git-setup-identity`, `git-add-project` and `git-update-project
  --signing-key` save the key either way, but turn on `commit.gpgsign` and
  `tag.gpgsign` only when gpg is installed, and warn otherwise.
- **No credential helper pointing at a CLI that isn't installed.** CLI
  wiring writes the project's `gh`/`glab` credential helper only when that
  CLI exists (git would otherwise have no helper for the host), and says to
  install it and run `git-sync-projects`, which writes the helper then.
- With `XDG_CONFIG_HOME` set to somewhere other than `~/.config`, CLI
  wiring checks the deployed `~/.config/direnv/lib/workbench-git-context.sh`
  (it checked the XDG path, where it never is) and warns once, with the
  `ln -s` to run, that direnv looks in `$XDG_CONFIG_HOME/direnv/lib`.
- **The `copilot` alias no longer hides a real `copilot`.** It is skipped
  when a `copilot` command is on `PATH` (workbench-ai installs GitHub's
  standalone Copilot CLI under that name); `upgrade-copilot` is unchanged.
- `get-git-functions` says what each function needs:
  `git-projects-base` is listed under yq v4, `git-add-project-cli` under
  "yq v4 (mikefarah/yq), and gh or glab", and `copilot`/`upgrade-copilot`
  under "gh with the gh-copilot extension". `git-projects-base` now fails
  with the yq error, rather than printing an empty path, when the projects
  manifest exists but yq doesn't work.

### Changed

- Requires workbench-core Core API 1.8 (`core_api: ">=1.8 <2.0"`) for the
  generated getter and `_wb_gh_release_asset_url`, which replaces this
  module's own copy in `install-yq` (workbench-core D90).
- Signing-key resolution uses workbench-gpg's public
  `gpg-resolve-signing-key` (when it is defined) instead of its private
  `_gpg_resolve_signing_key`, and `git-setup-identity` now resolves its key
  the same way as `git-add-project` and `git-update-project`. Without
  workbench-gpg the key is used as given, as before.
- The README says `wb tools install <name>`, not
  `install-<name>`.

### Removed

- **`git-remove-untracked`** (an alias for `git-cleanup`). The name says it
  removes untracked files; it force-deletes local branches whose upstream
  is gone. Use `git-cleanup` (or `gitcleanup`).

## [0.3.2] - 2026-10-26

### Fixed

- The "direnv is not installed" warning now points at `wb tools install
  direnv` rather than `install-direnv`, which can't be called from your
  shell. Required by workbench-core's module CI clean-shell check (its
  `docs/decisions-log.md` D94).

## [0.3.1] - 2026-10-24

### Fixed

- **`get-git-functions` now says what the project-management functions
  need.** Without a working mikefarah/yq v4, the seven yq-dependent
  functions are listed under "available once tooling is installed" with
  `yq v4 (mikefarah/yq) — install: wb tools install yq`, instead of only
  "7 more hidden". They are still defined and callable. Requires
  workbench-core Core API 1.7 (`core_api: ">=1.7 <2.0"`, workbench-core
  D86). The README now uses `wb tools install`, not the removed
  `wb tools update`.

## [0.3.0] - 2026-10-21

### Changed

- **Your `~/.gitconfig` stays yours; workbench-git's defaults sit
  underneath it** (workbench-core D82). The module now declares two
  gitconfig layers: workbench-core adds one marked block at the top of
  `~/.gitconfig` including `files/gitconfig` (`init.defaultBranch`,
  push/pull behaviour, colour, the excludes and attributes files) and one
  at the end including `files/gitconfig-contexts` (`profiles/local.inc`
  and your per-project identities). Anything you set outside the blocks
  wins. Opt out with `wb files policy git gitconfig skip`. Needs
  workbench-core 2.19.0 (Core API 1.6).
- **No post-deploy hook, so no `--allow-hooks`.** On the first update, the
  lines the old hook wrote into `~/.gitconfig` are removed (after a
  backup) and replaced by the blocks. `projects.yml` is created by
  `git-add-project` on first use; `git-list-projects` and
  `git-sync-projects` say "No projects yet" instead of failing.
- **`git-setup-identity` writes only the values you enter.** It no longer
  sets `init.defaultBranch`, `push.autoSetupRemote`, `pull.rebase`,
  `color.ui` or the excludes/attributes files — those come from the layer.
- **Works without workbench-shell** (workbench-core D83). With CLI contexts
  configured, the module hooks direnv into your shell itself when nothing
  else has.

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
