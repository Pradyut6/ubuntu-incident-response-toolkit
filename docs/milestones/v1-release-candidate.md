# v1.0.0 release candidate — implementation checkpoint

**Date:** 2026-11-05  
**Scope:** CLI source and documentation assembled in one working project folder; no GitHub publication.  
**Environment used for automated checks:** Linux build container running as a non-root test user (not the user's Ubuntu VirtualBox VM).

## Implemented

- CLI help/version, Ubuntu/WSL environment doctor and errors.
- Private incident store and JSON schema; create/list/show/note/status/search.
- Bounded host and allowlisted service/journal collection, before/after gzip evidence, partial status.
- Structured comparison, report generation, sanitized public export preview and SHA-256 archive.
- Configurable retention and explicit dry-run/confirmed pruning.
- 12 documented VM/fixture lab scenarios, rollback instructions, 12 KB drafts, case-study template.
- README, architecture, operations, security, testing and CI workflow.

## Tests actually executed on candidate

- `bash -n` for Bash source/tests — PASS.
- Portable smoke checks — 11 PASS.
- M3 secure-store regression checks — 20 PASS.
- v1 end-to-end integration checks — 28 PASS (includes >64 KiB compressed log, invalid archive, redaction, hashes and prune).
- Seeded redaction fixture script — PASS.
- Bash flow run from a fresh temporary runtime data root as an unprivileged Linux user.

## Gates not yet completed

- ShellCheck, shfmt and Bats on Ubuntu 24.04 — tools unavailable in this build container.
- Clean VM setup/restore and Nginx/SSH live collection.
- Twelve manual incident reproductions and observed before/after evidence.
- Measured runtime/storage performance and independent installation smoke test.
- Secrets/privacy audit on real captured evidence and GitHub release review.

**Release decision:** CODE ASSEMBLED / LOCAL NON-DESTRUCTIVE CHECKS PASS / VM ACCEPTANCE PENDING. Do not call any staged incident executed or resolved in the public resume yet.
