# Changelog

All notable changes to `workbench-git` are documented here.

## [Unreleased]

### Security

- **`GITHUB_PERSONAL_ACCESS_TOKEN` is no longer exported by default.** Both
  the eager, out-of-tree export in `shell/git.sh` and the per-project export
  in `use git_context` (`files/workbench-git-context.sh`) now require
  `export WORKBENCH_GIT_CONTEXT_EXPORT_TOKEN=true` in
  `~/.config/workbench/local/settings.sh` to opt in. An exported token is
  readable by every process the shell starts and typically carries `repo`
  and `workflow` scope.

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
