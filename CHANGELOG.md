# Changelog

Notable project changes are recorded here. This document distinguishes development milestones from **published releases**.

## [Unreleased]

No changes recorded since the v1.0.0 release preparation.

## [1.0.0] — 2026-11-14 — First CLI release (pending publication)

- **H01:** Added opt-in localhost-only HTTP status, timeout and duration observation with before/after comparisons.
- **H02:** Added TCP listening-address and expected-bind diagnostics with explicit socket-versus-service caution.
- **H03:** Added read-only target-filesystem capacity/inode observations, anonymized target fingerprints and WSL `ext2/ext3` stat-label compatibility.
- **H04:** Added direct systemd dependency inspection, including `.slice`/`.target` handling and bounded `Requires=` traversal.
- **H05:** Added bounded process sampling without command-line arguments; corrected the tool's own `ps` sampling artifact.
- **H06:** Added unit-scoped journal visibility metadata without retaining message content in the audit object.
- **H07:** Enforced actual decoded-byte limits on gzip inputs (including concatenated members), improved public export sanitization and report staging, and corrected failed filesystem comparability.
- Expanded automated regression to **13 stages**. Operator's Ubuntu 24.04 WSL 2 acceptance output reported exit `0`, including 28 baseline end-to-end checks.
- Executed twelve non-disruptive WSL 2 training exercises with explicit synthetic fixtures where appropriate. No native Ubuntu Server or VirtualBox acceptance has been claimed.
- **H08:** Revised operator-facing documentation and incident status; staged and committed the release candidate. Clean worktree passed 13/13 regression stages and an isolated host incident workflow. Final privacy/history review, v1.0.0 tag and GitHub publication remain pending.

> The CLI version is synchronized to `1.0.0` for final local verification. GitHub publication and the `v1.0.0` tag are still pending; earlier rc1 sections below are retained as historical milestones.

## [1.0.0-rc1] — 2026-11-05 — Initial CLI candidate

- Persistent incident lifecycle, notes, status and private store.
- Bounded host/service collection; immutable before/after snapshots and compressed evidence.
- Structured comparison, literal search, Markdown report, sanitized previewable handoff and SHA-256 manifest.
- Explicit retention dry-run and confirmed deletion; baseline smoke, integration and redaction tests.
- Initial twelve scenario runbooks and KB reference drafts; initial documentation and developer/CI scaffolding.
- At this checkpoint, later WSL 2 incident exercises and H01–H07 enhancements had **not yet been completed**.

## [0.2.0-dev] — 2026-11-05

- Private JSON store, incident create/list/show, validated permission and path rules.

## [0.1.0-dev] — 2026-11-05

- Bash CLI skeleton, read-only preflight and portable smoke checks.
