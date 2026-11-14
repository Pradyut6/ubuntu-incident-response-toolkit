# Operator handbook — Ubuntu Incident Response Toolkit

This handbook describes the **current H01–H07 CLI**, not the historical VirtualBox-first design. UIR targets Ubuntu 24.04 LTS and has been exercised on Ubuntu 24.04 under WSL 2. All collection commands are read-only and should be run as a regular user.

## 1. Preflight

```bash
./bin/uir --version
./bin/uir doctor
./bin/uir init
./bin/uir --help
```

If prerequisites are missing on Ubuntu, install the relevant packages (`jq`, `coreutils`, `tar`, `gzip`, `iproute2`, `curl`, `procps`; for development: `shellcheck`, `shfmt`, `bats`, `python3`). The tool does not create or change a systemd service. Use `sudo` **only** for separately reviewed manual administration—not for `./bin/uir`.

The private store is `${XDG_DATA_HOME:-$HOME/.local/share}/ubuntu-irt`. Do **not** place it under `/mnt/c` or commit it. Normal development may be performed on WSL 2; systemd service experiments must use **disposable named units or isolated servers**, and DNS, firewall and package-lock failures should be represented by safe fixtures rather than changes to the main environment.

## 2. Case lifecycle and immutable evidence

```bash
./bin/uir incident create --id INC-201 --service host --severity low \
  --summary 'Read-only WSL host inspection'
./bin/uir incident status --id INC-201 --value investigating
./bin/uir capture --incident INC-201 --phase before --minutes 5 \
  --fs-path / --processes
./bin/uir incident note --id INC-201 --kind hypothesis \
  --text 'Hypothesis pending further evidence'
# Perform only an independently reviewed, isolated intervention if needed.
./bin/uir capture --incident INC-201 --phase after --minutes 5 \
  --fs-path / --processes
./bin/uir compare --incident INC-201
./bin/uir incident note --id INC-201 --kind verification \
  --text 'State the check actually performed and its result'
./bin/uir incident status --id INC-201 --value resolved
./bin/uir report --incident INC-201
```

Replace `INC-201` with an unused ID. Each phase is immutable; another rehearsal requires a *new* incident. A host-only profile does not query an unrestricted journal.

## 3. Optional collectors and output keys

| Capture flag | Output key | Constraint / caveat |
| --- | --- | --- |
| `--http-port 18080` | `.http_probe` | Only `http://127.0.0.1:18080/`, `GET /`; no bodies or redirect-following; timeout is an outcome, not an HTTP status |
| `--listen-port 18080 --expect-address 127.0.0.1` | `.tcp_listener` | Socket binds are host-level, not an application ownership test; expected address requires port |
| `--fs-path /` | `.filesystem` | Contains mount capacity and inode usage; selected directory path fingerprinted |
| `--dependencies` | `.dependencies` | Allowed service profile only; at most 8 direct `Requires=` dependencies |
| `--processes` | `.processes` | Up to 8 processes, names without args; `ps` CPU is lifetime-average |
| `--journal-audit` | `.journal_audit` | Allowed service profile only; count/transport metadata; empty window does not prove broken logging |

Probe flags are optional and can be combined. If both phases do not use comparable targets, the corresponding comparison flag should be false or null. Do not treat a change in one-minute host load or a process's `ps` CPU percentage as proof of remediation.

```bash
SNAP="$HOME/.local/share/ubuntu-irt/incidents/INC-201/before/snapshot.json"
jq '{capture_status,collector_results,filesystem,processes}' "$SNAP"
```

**Nginx permission note:** On WSL 2, an ordinary-user `nginx -t` may fail because opening `/run/nginx.pid` requires elevated privileges. The collector correctly records `permission_limited`, making the overall snapshot `partial`. Check `collector_results` and `diagnostics.txt.gz`; verify separately with `sudo nginx -t` when justified. Never change `/run/nginx.pid` permissions to suppress the warning.

## 4. Search, notes, retention

```bash
./bin/uir incident list
./bin/uir incident show INC-201
./bin/uir incident search --since 2026-11-01 --text 'connection refused'
./bin/uir retention status
./bin/uir retention set --days 30 --max-storage-mb 500 --capture-max-mb 10
./bin/uir retention prune --dry-run
# Manually inspect the candidate list before this destructive action:
./bin/uir retention prune --yes
```

Pruning acts only on eligible private incident records and is never scheduled. Exported handoffs are not managed by retention.

## 5. Redacted handoff and integrity

```bash
./bin/uir export --incident INC-201 --preview
./bin/uir export --incident INC-201 --output "$HOME/INC-201-handoff.tar.gz"
```

Before extracting: inspect `tar -tvzf "$HOME/INC-201-handoff.tar.gz"` for unexpected entries, paths and links; only review archives you created or otherwise trust. Use an empty private directory with `0700` mode and verify `sha256sum -c SHA256SUMS` inside it. The hashes demonstrate content consistency, **not provenance or redaction completeness**. Review *all* JSON, Markdown and decompressed text manually. Don't publish private real incident exports.

## 6. Troubleshooting

| Symptom | Response |
| --- | --- |
| `expected a real private directory` | Call `uir init` if needed, then `incident create`; never hand-create incident directories |
| `snapshot already exists` | This phase is immutable. Keep it, choose a fresh incident ID for a new exercise |
| `unexpected capture argument` | Verify installer/CLI version, use flags as part of `uir capture`, not standalone commands |
| `partial` capture | Inspect `.collector_results` and compressed diagnostic warnings; do not overwrite status |
| Nginx `permission_limited` | Verify with separately authorized `sudo nginx -t`, not root `uir` |
| Unsupported service profile | Only `host`, `nginx`, `ssh`, `ssh.socket`, and validated disposable `uir-*` profiles |
| Gzip corruption / unsafe path | Preserve evidence privately, investigate; do not bypass validation or force export |
| Export already exists | Choose another safe destination; overwriting is deliberately refused |

For more detail see [architecture](architecture.md), [testing](testing.md), [security](security.md), and [incident execution tracker](incidents/STATUS.md).
