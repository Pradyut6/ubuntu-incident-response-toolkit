# Security model, trust boundaries and responsible use

UIR is a **local training and support-triage aid**, not a certified forensic instrument, enterprise SIEM or malware-resistant evidence store. The primary development and validation environment was **Ubuntu 24.04 under WSL 2** using disposable units and synthetic fixtures. Do not run fault injection against production, a school/work host, or your primary WSL networking/firewall/package database.

## Security defaults

- Run `./bin/uir` as a **regular user**. The CLI never escalates privileges, changes systemd unit files, or performs automatic remediation.
- Keep `$XDG_DATA_HOME/ubuntu-irt` (or `~/.local/share/ubuntu-irt`) on a trusted **Linux filesystem**. Private directories use `0700` and files `0600`, with validation for unsafe paths and symbolic links. Do not use `/mnt/c` for runtime evidence; Windows ACL semantics differ.
- Use strictly validated incident IDs, services, integers, time windows, directory targets and supported loopback values. No `eval` of user-controlled text or arbitrary probe URLs.
- Host-only captures do not execute unrestricted journal queries. Service journals are unit-scoped, bounded by time and line count; the extra H06 audit stores **counts and metadata**, not the `MESSAGE` field.
- HTTP probes are loopback-only and discard response bodies; TCP probes observe sockets without binding them to a claimed process. H03 stores a SHA-256 fingerprint instead of a raw filesystem path. H05 stores process names without their command-line arguments.
- Immutable snapshots are published from temporary private directories. Mutating commands use cooperative locks. The toolkit records partial collector failures rather than inventing complete diagnostics.
- Export uses an allowlist, separate private staging, public redaction, restricted output placement and no-overwrite behavior. H07 enforces an **actual decompressed-data ceiling** (including concatenated gzip members), sanitizes selected structured host/network fields, builds public reports from sanitized inputs and verifies sanitized comparison JSON.
- Export `SHA256SUMS` supports **integrity checks**, not authentication or authorship. Retention is explicitly invoked and never automatically prunes incident evidence.

## Privacy remains a human responsibility

Private diagnostics, journal records and operator notes may contain addresses, user names, tokens, secrets or sensitive context. Public-stage sanitization addresses recognized patterns, but **cannot guarantee anonymity or remove all secrets**. Review any proposed handoff member, including decompressed text/JSONL and reports, before external sharing. Never push real incident exports, SSH keys, internal logs, customer identifiers or personal Windows paths to GitHub.

Avoid placing secrets into sample commands and KBs. Only include **explicitly synthetic** sample data in public case studies. See [release checklist](release-checklist.md).

## Important limitations

- A hostile process with the **same UID** can race Bash-level file and symlink checks; this implementation does not use atomic `openat`-style secure file handles or provide multi-user forensic custody.
- `flock` coordinates cooperating writers; neither hashes nor local timestamps are cryptographic proof of trustworthy provenance.
- Bounds are best effort; this shell program is not kernel-enforced process-resource isolation.
- A TCP listener does not prove HTTP health or application ownership. HTTP 5xx is an observed application status, not a collector failure. `ps` CPU% is lifetime-average. Journal absence does not prove a broken logger. A successful process/service state alone does not establish an incident's root cause.
- Ubuntu/WSL systemd and journal permissions can limit visibility. Nginx checks can produce `permission_limited` in WSL 2 because of `/run/nginx.pid`; do not run the toolkit with `sudo` to suppress the warning.
- The WSL 2 test record does **not** prove parity with native Ubuntu Server, VirtualBox, or production systems.

## Responsible disclosure and validation

Report suspected security defects privately following [SECURITY.md](../SECURITY.md), using small synthetic reproductions rather than real secrets. Run `bash tests/run-all.sh` and verify no unexpected SKIP lines. For release, inspect the staged diff, URLs, case studies and export examples before pushing; see [testing](testing.md) and [release checklist](release-checklist.md).
