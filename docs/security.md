# Security model, threat boundaries and responsible use

The toolkit is a **training/portfolio incident-response aid**, not a certified forensic tool. It is meant for a disposable Ubuntu 24.04 VM and local support investigations. Never execute a fault-injection runbook against a host, WSL development distro, school/work system or customer environment.

## Defaults

- Run the CLI **without sudo**. The VM operator may perform manual `sudo` fixes following a reviewed lab procedure; the CLI never automatically repairs services.
- The store must be on a trusted Linux filesystem (`0700` directories, `0600` files); not on DrvFS (`/mnt/c`) or a shared Windows folder where UNIX ownership semantics may differ.
- IDs, unit/profile names, status fields, severities, lengths, dates and integer settings are validated. Logs and search text are treated as data; command text in messages is never executed.
- Host and service probes are bounded by timeouts and resource limits. The journal query is scoped to an allowlisted systemd unit (not full `/var/log`). The special `host` profile deliberately records no system journal.
- `uir init` and `incident create` make only private application files. `capture` adds private evidence; `report`, `compare` and export stage local files. The core does not change systemd configuration, firewall rules or permissions outside its own data root.
- Logs are stored as `gzip` text and JSON for portability. Compression saves space for typical repetitive logs but provides no guarantee of an exact compression ratio.
- Export redaction removes selected tokens, common cloud access-key shapes, emails, IPv4 addresses, home usernames and PEM private key boundaries. It is best effort; secrets in unusual formats, IPv6, embedded binary blobs, full private keys, and sensitive context may remain. **Manually inspect every export before publishing.**
- No telemetry, network upload, credentials collection, automatic failure-triggered monitoring, auto-repair, web server or GUI.

## What is not claimed

A malicious process running as the same UID as the operator can still race filesystem checks. This Bash implementation does not provide atomic openat-style path security; it is not appropriate for adversarial multi-user evidence custody. `flock` prevents cooperating concurrent writers but cannot defeat an attacker controlling the same user account. Metadata editing outside the application is not authenticated. Automatic pattern redaction cannot replace a privacy review.

## Verification and safe test exercises

Run `tests/run-all.sh` as an unprivileged user. Tests include mocked/fixture evidence, invalid ID and shell-like service strings, duplicate records, unsafe permissions, corruption, symlink prevention, gzip integrity, handoff hashes, seeded credentials and retention dry-run. Restore the VM snapshot after each deliberately broken system component.

## Release checklist

Before publication verify `git status`, inspect `git diff --cached`, ensure `.local`, VM images, raw journal files and secrets are absent, and search release source/examples for personal identifiers. Sanitized archive examples require a second human review. See [operations](operations.md) and [incident status](incidents/STATUS.md).
