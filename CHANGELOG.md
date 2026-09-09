# Changelog

All notable changes to `workbench-git` are documented here.

## [Unreleased]

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
