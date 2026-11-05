# Changelog

## [1.0.0-rc1] — 2026-11-05

- Implemented persistent incident lifecycle, operator notes and status.
- Added bounded host, Nginx, SSH/socket and `uir-*` training-unit collectors, including host-only profile.
- Added immutable before/after snapshots with compressed logs and explicit partial collector outcomes.
- Added literal evidence search, structured comparison and Markdown handoff report.
- Added previewable sanitized `.tar.gz` export with SHA-256 manifest and no-clobber publication.
- Added configurable retention age/storage limits and explicit dry-run/confirmed cleanup.
- Added automated smoke, regression, seeded redaction and 28-check end-to-end integration suite.
- Drafted 12 VM/fixture lab runbooks and 12 knowledge-base articles, with safe rollback and tracked evidence status.
- Rewrote README, architecture, operations, testing and security documentation.
- **Unverified:** Ubuntu VM acceptance, 12 staged incident exercises, full lint/format/Bats run on target host, GitHub publication.

## [0.2.0-dev] — 2026-11-05

- Private JSON store, incident create/list/show, validated path/permission rules.

## [0.1.0-dev] — 2026-11-05

- Bash CLI skeleton, read-only `doctor` and portable smoke checks.
